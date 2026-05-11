# Create buffered domain bounding box and write GeoParquet

#' Create a buffered bounding box around the domain
#'
#' @param domain The domain polygon sf object (output of domain_define).
#' @param buffer_m Numeric buffer distance in meters applied to the bbox (default 50 km).
#' @return The buffered bounding box as an sf object.
#' @details Builds the bounding box of the domain, converts to sf, buffers, and returns.
make_domain_bbox <- function(domain, buffer_m = 50000) {
  
  domain |> sf::st_bbox() |> sf::st_as_sfc() |> sf::st_buffer(buffer_m) |> sf::st_as_sf()

}
