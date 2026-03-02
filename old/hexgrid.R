hexgrid <- st_make_grid(
  domain,
  cellsize = c(500,500),
  offset = st_bbox(domain)[c("xmin", "ymin")],
  crs = st_crs(domain),
  what = "polygons",
  square = FALSE,
  flat_topped = FALSE
  ) |> 
  st_as_sf() |>
  st_intersection(domain) |> # keep all hexagons that intersect domain, not just those with centroids in domain
  mutate(pid = row_number())

