require_relative '../process_logger'
require 'nokogiri'
require_relative 'graph'
require_relative 'visual_graph'


# Class to load graph from various formats. Actually implemented is Graphviz formats. Future is OSM format.
class GraphLoader
  attr_reader :highway_attributes

  # Create an instance, save +filename+ and preset highway attributes
  def initialize(filename, highway_attributes)
    @filename = filename
    @highway_attributes = highway_attributes
  end

  # Load graph from Graphviz file which was previously constructed from this application, i.e. contains necessary data.
  # File needs to contain
  # => 1) For node its 'id', 'pos' (containing its re-computed position on graphviz space) and 'comment' containig string with comma separated lat and lon
  # => 2) Edge (instead of source and target nodes) might contains info about 'speed' and 'one_way'
  # => 3) Generaly, graph contains parametr 'bb' containing array withhou bounds of map as minlon, minlat, maxlon, maxlat
  #
  # @return [+Graph+, +VisualGraph+]
  def load_graph_viz()
    ProcessLogger.log("Loading graph from GraphViz file #{@filename}.")
    gv = GraphViz.parse(@filename)

    # aux data structures
    hash_of_vertices = {}
    list_of_edges = []
    hash_of_visual_vertices = {}
    list_of_visual_edges = []

    # process vertices
    ProcessLogger.log("Processing vertices")
    gv.node_count.times { |node_index|
      node = gv.get_node_at_index(node_index)
      vid = node.id

      v = Vertex.new(vid) unless hash_of_vertices.has_key?(vid)
      ProcessLogger.log("\t Vertex #{vid} loaded")
      hash_of_vertices[vid] = v

      geo_pos = node["comment"].to_s.delete("\"").split(",")
      pos = node["pos"].to_s.delete("\"").split(",")
      hash_of_visual_vertices[vid] = VisualVertex.new(vid, v, geo_pos[0], geo_pos[1], pos[1], pos[0])
      ProcessLogger.log("\t Visual vertex #{vid} in ")
    }

    # process edges
    gv.edge_count.times { |edge_index|
      link = gv.get_edge_at_index(edge_index)
      vid_from = link.node_one.delete("\"")
      vid_to = link.node_two.delete("\"")
      speed = 50
      one_way = false
      link.each_attribute { |k, v|
        speed = v if k == "speed"
        one_way = true if k == "oneway"
      }
      e = Edge.new(vid_from, vid_to, speed, one_way)
      list_of_edges << e
      list_of_visual_edges << VisualEdge.new(e, hash_of_visual_vertices[vid_from], hash_of_visual_vertices[vid_to])
    }

    # Create Graph instance
    g = Graph.new(hash_of_vertices, list_of_edges)

    # Create VisualGraph instance
    bounds = {}
    bounds[:minlon], bounds[:minlat], bounds[:maxlon], bounds[:maxlat] = gv["bb"].to_s.delete("\"").split(",")
    vg = VisualGraph.new(g, hash_of_visual_vertices, list_of_visual_edges, bounds)

    return g, vg
  end

  # Method to load graph from OSM file and create +Graph+ and +VisualGraph+ instances from +self.filename+
  #
  # @return [+Graph+, +VisualGraph+]
  def load_graph()
    nodes = {}
    vertices = {}
    visualVertices = {}
    edges = []
    visualEdges = []
    bounds = {}

    File.open(@filename, 'r') do |file|
      doc = Nokogiri::XML::Document.parse(file)

      doc.root.xpath('bounds').each do |bound|
        bounds[:minlon] = bound['minlon']
        bounds[:minlat] = bound['minlat']
        bounds[:maxlon] = bound['maxlon']
        bounds[:maxlat] = bound['maxlat']
      end

      doc.root.xpath('node').each do |node|
        nodes[node['id']] = node
      end

      doc.root.xpath('way').each do |way_element|
        speed = 50
        oneway = false
        continue = false

        way_element.xpath('tag').each do |tag_element|
          speed = tag_element['v'] if tag_element['k'] == 'maxspeed'
          oneway = true if tag_element['k'] == 'oneway'
          continue = true if tag_element['k'] == 'highway' && @highway_attributes.include?(tag_element["v"])
        end

        if continue
          (way_element.xpath('nd').count - 1).times do |i|
            from_nd_id = way_element.xpath('nd')[i]
            to_nd_id = from_nd_id.next_element['ref']

            from_node = nodes[from_nd_id['ref']]
            to_node = nodes[to_nd_id]

            # Create vertex, add into hash
            vertex = Vertex.new(to_nd_id)
            vertex2 = Vertex.new(from_nd_id['ref'])
            vertices[to_nd_id] = vertex unless vertices.has_key?(to_nd_id)
            vertices[from_nd_id['ref']] = vertex2 unless vertices.has_key?(from_nd_id['ref'])

            # Create visual vertex
            visual_vertex2 = VisualVertex.new(to_nd_id, to_node, to_node['lat'], to_node['lon'], to_node['lat'], to_node['lon'])
            visual_vertex = VisualVertex.new(from_node['id'], from_node, from_node['lat'], from_node['lon'], from_node['lat'], from_node['lon'])
            visualVertices[from_node['id']] = visual_vertex unless visualVertices.has_key?(from_node['id'])
            visualVertices[to_node['id']] = visual_vertex2 unless visualVertices.has_key?(to_node['id'])

            # Create edge
            edge = Edge.new(vertex, vertex2, speed, oneway)
            edges << edge
            edge.distance = calculate_distance([from_node['lat'].to_f, from_node['lon'].to_f], [to_node['lat'].to_f, to_node['lon'].to_f])

            # Create visual edge
            visualEdge = VisualEdge.new(edge, visual_vertex, visual_vertex2)
            visualEdges << visualEdge
          end
        end
      end
    end

    # Create graph, visual graph
    graph = Graph.new(vertices, edges)
    visualGraph = VisualGraph.new(graph, visualVertices, visualEdges, bounds)

    # Find largest component
    largest_comp = find_component(graph)

    # Filter vertices and edges from largest component and create graphs from largest component
    filtered_edges = graph.edges.reject { |edge|  !largest_comp.include?(edge.v1.id) || !largest_comp.include?(edge.v2.id)}
    filtered_vertices = graph.vertices.reject { |vertex|  !largest_comp.include?(vertex)}
    filter_visual_edges = visualGraph.visual_edges.reject { |vis_edge| !largest_comp.include?(vis_edge.v1.id) || !largest_comp.include?(vis_edge.v2.id)}
    filter_visual_vertices = visualGraph.visual_vertices.reject { |vis_vertex|  !largest_comp.include?(vis_vertex)}

    graph = Graph.new(filtered_edges,filtered_vertices)
    visualGraph = VisualGraph.new(graph, filter_visual_vertices, filter_visual_edges, bounds)

    return graph, visualGraph
  end



  def calculate_distance loc1, loc2
    rad_per_deg = Math::PI / 180 # PI / 180
    rkm = 6371 # Earth radius in kilometers
    rm = rkm * 1000 # Radius in meters

    dlat_rad = (loc2[0] - loc1[0]) * rad_per_deg # Delta, converted to rad
    dlon_rad = (loc2[1] - loc1[1]) * rad_per_deg

    lat1_rad, lon1_rad = loc1.map { |i| i * rad_per_deg }
    lat2_rad, lon2_rad = loc2.map { |i| i * rad_per_deg }

    a = Math.sin(dlat_rad / 2) ** 2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlon_rad / 2) ** 2
    c = 2 * Math::atan2(Math::sqrt(a), Math::sqrt(1 - a))

    rm * c # Delta in meters
  end

  def find_component(graph)
    biggest = []
    used_vertices = []

    while biggest.length < (graph.vertices.length - used_vertices.length)
      node = graph.vertices.select{|vertex| !used_vertices.include?(vertex)}.to_a
      component = bfs(node, graph)

      if component.length > biggest.length
        biggest = component
      end
      used_vertices.push(*component)
    end
    return biggest
  end

  def bfs(node, graph)
    node = node[0][1]
    queue = []
    visited = []
    queue << node
    visited << node.id

    while queue.any?
      current_node = queue.shift # remove first element
      edges = graph.edges.select{|edge| edge.v1.id == current_node.id || edge.v2.id == current_node.id }
      edges.each do |edge|
        if !visited.include?(edge.v2.id)
          queue << edge.v2
          visited << edge.v2.id
        end
        if !visited.include?(edge.v1.id)
          queue << edge.v1
          visited << edge.v1.id
        end
      end
    end
    return visited
  end
end

