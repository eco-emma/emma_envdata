# Create buffered domain bounding box and write GeoParquet

#' Create a buffered bounding box around the domain
#'
#' @param domain_parquet Path to domain polygon GeoParquet (output of domain_define).
#' @param buffer_m Numeric buffer distance in meters applied to the bbox (default 50 km).
#' @param out_file Output GeoParquet path (default data/raw/domain_bbox.parquet).
#' @return Character path to the written GeoParquet file.
#' @details Reads the domain polygon, builds its bounding box, converts to sf, buffers, and writes to GeoParquet.
make_domain_bbox <- function(domain_parquet, buffer_m = 50000, out_file = "data/target_outputs/domain_bbox.parquet") {
  domain_sf <- sfarrow::st_read_parquet(domain_parquet)
  bbox_geom <- domain_sf |> sf::st_bbox() |> sf::st_as_sfc() |> sf::st_buffer(buffer_m)
  bbox_sf <- sf::st_as_sf(bbox_geom)
  sfarrow::st_write_parquet(bbox_sf, out_file)
  out_file
}
