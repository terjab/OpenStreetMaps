# Class representing visual representation of edge
class VisualEdge
  # Starting +VisualVertex+ of this visual edge
  attr_reader :v1
  # Target +VisualVertex+ of this visual edge
  attr_reader :v2
  # Corresponding edge in the graph
  attr_reader :edge
  # Boolean value given directness
  attr_reader :directed
  # Boolean value emphasize character - drawn differently on output (TODO)
  attr_reader :emphesized

  attr_reader :color

  attr_reader :penwidth


  # create instance of +self+ by simple storing of all parameters
  def initialize(edge, v1, v2)
  	@edge = edge
    @v1 = v1
    @v2 = v2
    @color = "black"
    @penwidth = 2
  end

  def set_color(color)
    @color = color
  end

  def set_penwidth(penwidth)
    @penwidth = penwidth
  end
end

