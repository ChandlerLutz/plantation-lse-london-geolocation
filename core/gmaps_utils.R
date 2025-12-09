## core/gmaps_utils.R

## gmaps_api <- keyring::key_set("gmaps_lse_key")
gmaps_api_key <- keyring::key_get("gmaps_lse_key")

ggmap::register_google(key = gmaps_api_key)

get_gmaps_cleaned_london_address <- function(addr_vec) {
  dt <- data.table(original_address = addr_vec)
  dt[, london_address_cleaned := gsub("\\.", "", original_address)]
  
  dt[, london_address_cleaned := sapply(london_address_cleaned, function(x) {
    parts <- trimws(strsplit(x, ",")[[1]])
    if (length(parts) >= 4) {
      last_part <- toupper(parts[length(parts)])
      is_london_dist <- grepl("^(EC|WC|SW|SE|NW|N|E|W|S)[0-9]*[A-Z]?$", last_part)
      starts_num <- grepl("^[0-9]", parts[1])
      if (is_london_dist && starts_num) {
        return(paste(parts[1], parts[2], parts[length(parts)]))
      }
    }
    return(paste(parts, collapse = " "))
  })]
  
  dt[, london_address_gmaps_input := sapply(london_address_cleaned, function(x) {
    if (is.na(x) || x == "") return(NA_character_) 
    
    lower_x <- tolower(x)
    
    if (grepl("antwerp", lower_x)) return(paste0(x, ", Belgium"))
    if (grepl("jersey city", lower_x)) return(paste0(x, ", USA"))
    if (grepl("copenhagen", lower_x)) return(paste0(x, ", Denmark"))
    if (grepl("amsterdam", lower_x)) return(paste0(x, ", Netherlands"))
    if (grepl("dublin", lower_x)) return(paste0(x, ", Ireland"))
    
    if (grepl("edinburgh|glasgow|liverpool|manchester|birmingham|aberdeen|perth|ipswich|ross-shire|avoch|fortrose", lower_x)) {
      if (grepl("nb$", lower_x)) return(gsub("NB$", "Scotland, UK", x, ignore.case=TRUE))
      return(paste0(x, ", UK"))
    }
    
    if (!grepl("london", lower_x)) return(paste0(x, ", London, UK"))
    return(paste0(x, ", UK"))
  })]
  return(dt$london_address_gmaps_input)
}

geocode_london_robust_detailed <- function(place_string) {
  
  box::use(
    ggmap[has_google_key, geocode], 
    data.table[data.table, fcase, as.data.table],
    sf[st_point, st_polygon, st_sfc, st_distance]
  )
  
  if (!has_google_key()) {
    stop("Google Maps API key not set. Use ggmap::register_google().")
  }
  
  if (is.na(place_string) || place_string == "") return(NULL)

  # --- 1. Define Helper to call API ---
  call_api <- function(query) {
    tryCatch({
      res <- geocode(location = query, output = "all", override_limit = TRUE)
      if (is.null(res) || res$status != "OK" || length(res$results) == 0) return(NULL)
      return(res$results[[1]])
    }, error = function(e) return(NULL))
  }

  # --- 2. Cascading Retry Logic ---
  
  # Attempt A: Exact Match
  final_res <- call_api(place_string)
  match_method <- "Exact Match"
  actual_query <- place_string
  
  # Attempt B: Drop District (e.g., "7 Martin Lane, London, UK")
  if (is.null(final_res)) {
    query_no_district <- gsub("\\s[A-Z]{1,3}[0-9A-Z]*\\,\\s*London", ", London", place_string, ignore.case = TRUE)
    if (query_no_district != place_string) {
      final_res <- call_api(query_no_district)
      match_method <- "Retry: Removed District"
      actual_query <- query_no_district
    }
  }
  
  # Attempt C: Drop House Number (e.g., "Martin Lane, London, UK")
  if (is.null(final_res)) {
    query_street_only <- gsub("^[0-9]+[A-Z]?\\,?\\s*", "", actual_query)
    if (query_street_only != actual_query) {
      final_res <- call_api(query_street_only)
      match_method <- "Retry: Street Centroid"
      actual_query <- query_street_only
    }
  }

  if (is.null(final_res)) {
    warning(paste("Geocoding failed for:", place_string))
    return(NULL)
  }

  # --- 3. Robust Extraction Functions ---
  safe_pluck_num <- function(l, ...) {
    path <- list(...)
    val <- l
    for (p in path) {
      val <- val[[p]]
      if (is.null(val)) return(NA_real_)
    }
    if (is.numeric(val)) return(val) else return(NA_real_)
  }

  safe_pluck_char <- function(l, ...) {
    path <- list(...)
    val <- l
    for (p in path) {
      val <- val[[p]]
      if (is.null(val)) return(NA_character_)
    }
    return(as.character(val))
  }
  
  extract_component <- function(components, type) {
    if (is.null(components)) return(NA_character_)
    match <- Filter(function(x) type %in% x$types, components)
    if (length(match) > 0) return(match[[1]]$long_name) else return(NA_character_)
  }

  res <- final_res

  # --- 4. Bounding Box Fallback Logic ---
  ne_lat <- safe_pluck_num(res, "geometry", "bounds", "northeast", "lat")
  if (is.na(ne_lat)) ne_lat <- safe_pluck_num(res, "geometry", "viewport", "northeast", "lat")
  
  ne_lon <- safe_pluck_num(res, "geometry", "bounds", "northeast", "lng")
  if (is.na(ne_lon)) ne_lon <- safe_pluck_num(res, "geometry", "viewport", "northeast", "lng")
  
  sw_lat <- safe_pluck_num(res, "geometry", "bounds", "southwest", "lat")
  if (is.na(sw_lat)) sw_lat <- safe_pluck_num(res, "geometry", "viewport", "southwest", "lat")
  
  sw_lon <- safe_pluck_num(res, "geometry", "bounds", "southwest", "lng")
  if (is.na(sw_lon)) sw_lon <- safe_pluck_num(res, "geometry", "viewport", "southwest", "lng")

  # --- 5. Build Data Table ---
  dt <- data.table(
    # --- QUERY INFO ---
    gmaps_place_query_string = place_string,
    gmaps_actual_query = actual_query,
    gmaps_match_method = match_method,  # <--- How we found it (Exact vs Retry)
    
    # --- GOOGLE METADATA ---
    gmaps_place_type = safe_pluck_char(res, "types", 1),
    gmaps_location_type = safe_pluck_char(res, "geometry", "location_type"), # <--- ROOFTOP vs APPROXIMATE
    
    # --- COORDINATES ---
    gmaps_lon = safe_pluck_num(res, "geometry", "location", "lng"),
    gmaps_lat = safe_pluck_num(res, "geometry", "location", "lat"),
    gmaps_formatted_address = safe_pluck_char(res, "formatted_address"),
    gmaps_place_id = safe_pluck_char(res, "place_id"),
    
    # --- COMPONENTS ---
    gmaps_city = extract_component(res$address_components, "postal_town"),
    gmaps_borough = extract_component(res$address_components, "administrative_area_level_2"),
    gmaps_state = extract_component(res$address_components, "administrative_area_level_1"),
    gmaps_country = extract_component(res$address_components, "country"),
    gmaps_postal_code = extract_component(res$address_components, "postal_code"),
    
    # --- BOUNDING BOX ---
    gmaps_bbox_ne_lat = ne_lat,
    gmaps_bbox_ne_lon = ne_lon,
    gmaps_bbox_sw_lat = sw_lat,
    gmaps_bbox_sw_lon = sw_lon
  )

  # --- 6. Uncertainty Radius & Geometry Creation (sf) ---
  if (all(!is.na(c(dt$gmaps_bbox_sw_lon, dt$gmaps_bbox_sw_lat, dt$gmaps_bbox_ne_lon, dt$gmaps_bbox_ne_lat)))) {
    
    coords <- matrix(c(
      dt$gmaps_bbox_sw_lon, dt$gmaps_bbox_sw_lat,
      dt$gmaps_bbox_sw_lon, dt$gmaps_bbox_ne_lat,
      dt$gmaps_bbox_ne_lon, dt$gmaps_bbox_ne_lat,
      dt$gmaps_bbox_ne_lon, dt$gmaps_bbox_sw_lat,
      dt$gmaps_bbox_sw_lon, dt$gmaps_bbox_sw_lat
    ), ncol = 2, byrow = TRUE)
    
    bbox_poly <- st_polygon(list(coords))
    dt[, gmaps_bbox_polygon := list(st_sfc(bbox_poly, crs = 4326))]
    
    # Calculate Uncertainty Radius
    sw_pt <- st_sfc(st_point(c(dt$gmaps_bbox_sw_lon, dt$gmaps_bbox_sw_lat)), crs = 4326)
    ne_pt <- st_sfc(st_point(c(dt$gmaps_bbox_ne_lon, dt$gmaps_bbox_ne_lat)), crs = 4326)
    
    diag_dist <- as.numeric(st_distance(sw_pt, ne_pt))
    dt[, gmaps_uncertainty_radius_m := diag_dist / 2]
    
  } else {
    dt[, gmaps_bbox_polygon := list(st_sfc(st_polygon(), crs = 4326))]
    dt[, gmaps_uncertainty_radius_m := NA_real_]
  }

  if (!is.na(dt$gmaps_lon) && !is.na(dt$gmaps_lat)) {
    center_point <- st_point(c(dt$gmaps_lon, dt$gmaps_lat))
    dt[, gmaps_center_point := list(st_sfc(center_point, crs = 4326))]
  }
    
  return(dt)
}
