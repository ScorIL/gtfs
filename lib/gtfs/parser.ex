defmodule GTFS.Parser do
  alias GTFS.Route
  alias GTFS.Shape
  alias GTFS.Data

  @route_headers ~w(
    route_id
    agency_id
    route_short_name
    route_long_name
    route_desc
    route_type
    route_url
    route_color
    route_text_color
  )

  @gtfs_files ~w(routes trips stops shapes)a

  def parse(folder) do
    load_csv_streams(folder)
    |> normalize_streams
    |> to_maps
    |> insert_shapes_into_routes
    |> to_structs
    |> insert_route_short_name_map
    |> Map.take([:routes, :route_short_names])
    |> GTFS.Data.from_map
  end

  def normalize_streams(streams) do
    streams
    |> Enum.map(&normalize_stream/1)
    |> Enum.into(%{})
  end

  def normalize_stream({key, stream}) do
    {key, Stream.map(stream, fn attr_map -> normalize_map(attr_map, key) end)}
  end

  def normalize_map(attr_map, :routes) do
    id = Regex.replace(~r/[^0-9]/, attr_map["route_id"], "")
    short_name = Map.get(attr_map, "route_short_name", "")
    color = Map.get(attr_map, "route_color", "")

    attr_map
    |> Map.put("route_id", Regex.replace(~r/[^0-9]/, attr_map["route_id"], ""))
    |> Map.put("route_short_name", Regex.replace(~r/[^0-9]/, short_name, ""))
    |> Map.put("route_color", "#" <> color)
  end
  def normalize_map(attr_map, _) do
    attr_map
  end

  def to_maps(streams) do
    Enum.reduce(Map.keys(streams), streams, &to_map/2)
  end

  def to_map(:routes, streams) do
    routes =
      streams[:routes]
      |> Stream.map(fn route -> {route["route_id"], route} end)

    Map.put(streams, :routes, routes)
  end
  def to_map(:trips, streams) do
    trips =
      streams[:trips]
      |> Stream.map(fn trip -> {trip["trip_id"], trip} end)

    Map.put(streams, :trips, trips)
  end
  def to_map(:shapes, streams) do
    shapes =
      streams[:shapes]
      |> Enum.reduce(%{}, fn(r, acc) -> # TODO - how to keep this as a stream?
        Map.update(acc, r["shape_id"], [], &([r | &1]))
      end)

    Map.put(streams, :shapes, shapes)
  end
  def to_map(:stops, streams) do
    stops =
      streams[:stops]
      |> Stream.map(fn stop -> {stop["stop_id"], stop} end)

    Map.put(streams, :stops, stops)
  end

  def insert_shapes_into_routes(streams) do
    routes =
      streams[:routes]
      |> Stream.map(fn {route_id, route} ->
        shapes = shapes_for_route(route_id, streams[:trips], streams[:shapes])
        {route_id, Map.put(route, "shapes", shapes)}
      end)

    Map.put(streams, :routes, routes)
  end

  def shapes_for_route(route_id, trips, shapes) do
    trips
    |> Stream.filter(fn {_id, t} -> t["route_id"] == route_id end)
    |> Stream.map(fn {_id, t} -> t["shape_id"] end)
    |> Stream.uniq
    |> Stream.flat_map(fn shape_id -> shapes[shape_id] end)
  end

  def to_structs(streams) do
    routes =
      streams[:routes]
      |> Stream.map(fn {id, r} -> {id, Route.from_map(r)} end)
      |> Stream.map(fn {id, r} ->
        # insert shapes
        route = Map.update(r, :shapes, [], fn s ->
          Enum.map(s, &Shape.from_map/1)
        end)
        {id, route}
      end)
      |> Enum.into(%{})

    Map.put(streams, :routes, routes)
  end

  def insert_route_short_name_map(streams) do
    short_name_map =
      streams[:routes]
      |> Enum.map(fn {_id, r} -> {r.route_short_name, r.route_id} end)
      |> Enum.into(%{})

    Map.put(streams, :route_short_names, short_name_map)
  end

  def load_csv_streams(folder) do
    @gtfs_files
    |> Enum.map(fn file -> {file, csv_stream(folder, file)} end)
    |> Enum.into(%{})
  end

  def csv_stream(folder, file) do
    Path.join([folder, "#{file}.txt"])
    |> File.stream!
    |> CSV.decode(headers: true)
  end
end
