require 'ruby-graphviz'
require_relative 'visual_edge'
require_relative 'visual_vertex'
MAXINT = 2147483647


# Visual graph storing representation of graph for plotting.
class VisualGraph
  # Instances of +VisualVertex+ classes
  attr_reader :visual_vertices
  # Instances of +VisualEdge+ classes
  attr_reader :visual_edges
  # Corresponding +Graph+ Class
  attr_reader :graph
  # Scale for printing to output needed for GraphViz
  attr_reader :scale

  # Create instance of +self+ by simple storing of all given parameters.
  def initialize(graph, visual_vertices, visual_edges, bounds)
    @graph = graph
    @visual_vertices = visual_vertices
    @visual_edges = visual_edges
    @bounds = bounds
    @scale = ([bounds[:maxlon].to_f - bounds[:minlon].to_f, bounds[:maxlat].to_f - bounds[:minlat].to_f].min).abs / 10.0
    @distance
    @time
  end

  # Export +self+ into Graphviz file given by +export_filename+.
  def export_graphviz(export_filename)
    # create GraphViz object from ruby-graphviz package
    graph_viz_output = GraphViz.new(:G,
                                    use: :neato,
                                    truecolor: true,
                                    inputscale: @scale,
                                    margin: 0,
                                    bb: "#{@bounds[:minlon]},#{@bounds[:minlat]},
                                  		    #{@bounds[:maxlon]},#{@bounds[:maxlat]}",
                                    outputorder: :nodesfirst)

    # append all vertices
    @visual_vertices.each { |k, v|
      graph_viz_output.add_nodes(v.id, :shape => 'point',
                                 :comment => "#{v.lat},#{v.lon}!",
                                 :pos => "#{v.y},#{v.x}!",
                                 :color => v.color,
                                 :width => v.width)
    }

    # append all edges
    @visual_edges.each { |edge|
      graph_viz_output.add_edges(edge.v1.id, edge.v2.id, 'arrowhead' => 'none', 'color' => edge.color, 'penwidth' => edge.penwidth)
    }

    # export to a given format
    format_sym = export_filename.slice(export_filename.rindex('.') + 1, export_filename.size).to_sym
    graph_viz_output.output(format_sym => export_filename)
  end

  def dijkstra(source, toId)
    @distances = {}
    @previous = {}

    @visual_vertices.each do |vertex|
      @distances[vertex[0]] = Float::INFINITY
      @previous[vertex[0]] = nil
    end

    @distances[source] = 0
    unvisited_nodes = @visual_vertices.clone
    current_vertexes = []

    while unvisited_nodes.count != 0

      current_vertexes = unvisited_nodes.keys.group_by { |node| @distances[node] }.min_by(&:first).last
      curr = current_vertexes[0]

      break if @distances[curr] == Float::INFINITY
      unvisited_nodes.delete(curr)

      if current_vertexes.include?(toId)
        shortest_path = find_path_between_nodes(toId)
        time = @distances[toId]
        return shortest_path, time
      end

      related_edges = @visual_edges.select { |edge| current_vertexes.include?(edge.v1.id) || current_vertexes.include?(edge.v2.id) }

      related_edges.each do |edge|
        current = nil

        if current_vertexes.include?(edge.v1.id)
          current = edge.v1.id
          neighbour = edge.v2.id
        else
          neighbour = edge.v1.id
          current = edge.v2.id
        end

        weight = @distances[current] + (edge.edge.distance.to_f / edge.edge.max_speed.to_f * 0.06)
        if (weight < @distances[neighbour])
          @distances[neighbour] = weight
          @previous[neighbour] = current
        end
      end
      current_vertexes = []
    end
  end

  def find_shortest_way(fromId, toId)
    dijkstra(fromId, toId)
  end

  def print_time(time)
    p "Time in minutes: #{time}"
  end

  def find_path_between_nodes(dest)
    v = dest
    @path = []
    while v != nil
      @path.unshift(v)
      v = @previous[v]
    end
    return @path
  end


  def mark_way(way)
    @visual_edges.select { |edge| way.include?(edge.v1.id) && way.include?(edge.v2.id)}.map {|edge| edge.set_color("red") && edge.set_penwidth(3)}

    way.each do |w|
      @visual_vertices[w].set_color("red")
      @visual_vertices[w].set_width("0.2")
    end
  end

  def mark_start_end_vertices(start, finish)
    @visual_vertices[start].set_color("red")
    @visual_vertices[start].set_width(0.2)
    @visual_vertices[finish].set_color("red")
    @visual_vertices[finish].set_width(0.2)
  end

  def get_nearest_nodes(lat_start, lat_stop, lon_start, lon_stop)
    nearest_to_start_id = nil
    nearest_start_distance = nil
    nearest_to_end_id = nil
    nearest_end_distance = nil

    @visual_vertices.each do |vertex|
      calculate_start_distance = calculate_distance([lat_start, lon_start], [vertex[1].lat.to_f, vertex[1].lon.to_f])
      calculate_end_distance = calculate_distance([lat_stop, lon_stop], [vertex[1].lat.to_f, vertex[1].lon.to_f])

      if nearest_start_distance == nil || nearest_start_distance > calculate_start_distance
        nearest_start_distance = calculate_start_distance
        nearest_to_start_id = vertex[1].id
      end

      if nearest_end_distance == nil || nearest_end_distance > calculate_end_distance
        nearest_end_distance = calculate_end_distance
        nearest_to_end_id = vertex[1].id
      end
    end

    @id_start = nearest_to_start_id
    @id_end = nearest_to_end_id

    return nearest_to_start_id, nearest_to_end_id
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

end


