## ./010-get_gmaps_geolocation.R

##Clear the workspace
rm(list = ls()) 
suppressWarnings(CLmisc::detach_all_packages())

##Set wd using the here package
setwd(here::here("./"))

suppressPackageStartupMessages({library(CLmisc); })

gmaps_utils <- load_module(here::here("core/gmaps_utils.R"))

dt <- fread("./data-raw/unique_london_company_secretary.csv") %>%
  .[, london_address_gmaps_input := gmaps_utils$get_gmaps_cleaned_london_address(
    london_address_cleaned
  )]

f_get_gmaps_geolocation <- function(location_string) {
  dt_out <- try({
    gmaps_utils$geocode_london_robust_detailed(location_string)
  }, silent = FALSE)

  if (inherits(dt_out, "try-error")) {
    warning(paste("Geocoding failed for location:", location_string))
    return(data.table(
      gmaps_geolocation_input = location_string
    ))
  } else {

    dt_out <- dt_out[, london_address_gmaps_input := location_string] %>%
      setcolorder(c("london_address_gmaps_input"))
    return(dt_out)
  }
}

## tmp1 <- gmaps_utils$geocode_london_robust_detailed("7 Martin Lane EC, London, UK")
## tmp2 <- f_get_gmaps_geolocation(
##   dt[!is.na(london_address_gmaps_input), unique(london_address_gmaps_input)][11]
## )

dt_gmaps_geolocation <- lapply(
  dt[!is.na(london_address_gmaps_input), unique(london_address_gmaps_input)],
  f_get_gmaps_geolocation
) %>%
  rbindlist(use.names = TRUE, fill = TRUE) %>%
  .[order(london_address_gmaps_input)]

dt_out <- merge(dt, dt_gmaps_geolocation, by = "london_address_gmaps_input",
                all.x = TRUE) %>%
  setcolorder(c("london_address_cleaned", "london_address_gmaps_input"))

num_offices_found_geolocation <- dt_out %>%
  .[!is.null(gmaps_center_point) & !sf::st_is_empty(gmaps_center_point)] %>%
  nrow()
num_offices_missing_geolocation <- dt_out %>%
  .[is.null(gmaps_center_point) | sf::st_is_empty(gmaps_center_point)] %>%
  nrow()
message(paste0(
  "Number of London company secretary offices with geolocation found: ",
  num_offices_found_geolocation,
  "\nNumber of London company secretary offices missing geolocation: ",
  num_offices_missing_geolocation
))

saveRDS(
  dt_out,
  file = here::here("work/020-dt_london_company_secretary_gmaps_geolocation.rds")
)

library(sf); library(dplyr)

dt_out <- readRDS(
  here::here("work/020-dt_london_company_secretary_gmaps_geolocation.rds")
)

if (any(sapply(dt_out$gmaps_center_point, is.null))) {
  null_pts <- sapply(dt_out$gmaps_center_point, is.null)
  dt_out$gmaps_center_point[null_pts] <- lapply(1:sum(null_pts), function(x) st_point())
}

if (any(sapply(dt_out$gmaps_bbox_polygon, is.null))) {
  null_bbox <- sapply(dt_out$gmaps_bbox_polygon, is.null)
  dt_out$gmaps_bbox_polygon[null_bbox] <- lapply(1:sum(null_bbox), function(x) st_polygon())
}

dt_sf <- st_as_sf(dt_out, sf_column_name = "gmaps_center_point", crs = 4326)

dt_sf <- dt_sf %>%
  mutate(across(where(is.list) & !all_of(c("gmaps_center_point", "gmaps_bbox_polygon")), as.character))

output_file <- "work/020-london_company_secretary_gmaps_geolocation.gpkg"

points_layer <- dt_sf %>%
  select(-gmaps_bbox_polygon)

st_write(points_layer, dsn = output_file, layer = "companies_points", delete_layer = TRUE)

bbox_layer <- dt_sf %>%
  st_set_geometry("gmaps_bbox_polygon") %>%
  select(-gmaps_center_point)

st_write(bbox_layer, dsn = output_file, layer = "companies_bbox", delete_layer = TRUE)
