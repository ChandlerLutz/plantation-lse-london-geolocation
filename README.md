# Historical London Company Geocoding (Early 20th Century)

This repository contains the code and data workflow for cleaning, standardizing, and geocoding historical London company addresses from the early 20th century. It utilizes the Google Maps Geocoding API with a robust, cascading retry logic to handle historical address formats and outdated postal districts.

## Project Overview

The primary goal of this project is to assign accurate spatial coordinates (latitude/longitude) to a dataset of historical companies listed in London. The workflow addresses specific challenges associated with early 20th-century data:
* **Reference Streets:** Removing descriptive locators common in historical directories (e.g., *"Martin Lane, Cannon Street"* vs. modern *"Martin Lane"*).
* **Historical Districts:** Handling outdated postal districts (e.g., *"E.C."*) that may not align with modern boundaries.
* **Ambiguity:** Providing uncertainty metrics (bounding box area and uncertainty radius) to quantify the precision of each match.
* **GIS Interoperability:** Exporting data to standard GeoPackage (`.gpkg`) format with separate layers for point locations and uncertainty bounding boxes.

## Repository Structure

```
.
├── core/
│   ├── gmaps_utils.R          # Core functions for API interaction, cleaning, and spatial calculations
├── data-raw/
│   └── unique_london_company_secretary.csv  # Original input dataset of companies and addresses
├── work/
│   ├── 020-dt_london_company_secretary_gmaps_geolocation.rds  # Final processed R data object
│   └── 020-london_company_secretary_gmaps_geolocation.gpkg    # Final GIS file (Points & BBoxes)
├── 010-get_gmaps_geolocation.R  # Main execution script
└── README.md
```
## Methodology

### 1. Address Cleaning (`core/gmaps_utils.R`)
Before geocoding, addresses are pre-processed to maximize API compatibility:
* **Standardization:** Removal of dots in abbreviations (e.g., "S.W.1" -> "SW1").
* **Simplification:** Algorithmic removal of "reference streets" (e.g., turning *"7, Martin Lane, Cannon Street, E.C."* into *"7 Martin Lane EC"*).
* **Contextualization:** Appending "London, UK" or specific country names for international addresses (e.g., Antwerp, Glasgow).

### 2. Robust Geocoding (`core/gmaps_utils.R`)
The `geocode_london_robust_detailed()` function employs a cascading logic to handle historical ambiguities:
1.  **Attempt 1 (Exact Match):** Queries the full, cleaned address string.
2.  **Attempt 2 (District Removal):** If the exact match fails (common with historical boundaries), it retries without the postal district (e.g., *"7 Martin Lane, London"*).
3.  **Attempt 3 (Street Centroid):** If the specific building number fails, it falls back to the street centroid.

### 3. Output Generation (`010-get_gmaps_geolocation.R`)
The pipeline produces a **GeoPackage (`.gpkg`)** containing two distinct layers for use in GIS software (QGIS, ArcGIS):
* **`companies_points`**: The specific geocoded coordinate (centroid or rooftop).
* **`companies_bbox`**: The bounding box polygon representing the area of uncertainty (e.g., the full street length if a specific building wasn't found).

## Usage

### Prerequisites
* **R** (packages: `data.table`, `sf`, `ggmap`, `keyring`, `magrittr`, `here`, `CLmisc`, `dplyr`).
* A valid Google Maps API Key stored in your system keyring under the service name `gmaps_lse_key`.

### Running the Pipeline
Execute the main script to process the raw CSV, geocode the addresses, and generate the output files:

source("010-get_gmaps_geolocation.R")

## Authors

* **Valeria Giacomin**
* **Chandler Lutz**


## Citation

If you use this code or data in your research, please cite:

> Giacomin, V. & Lutz, C. (2025). *Historical London Company Geocoding Pipeline (Early 20th Century)* [Computer software]. GitHub. https://github.com/ChandlerLutz/plantation-lse-london-geolocation

```
@software{Lutz_Giacomin_2025,
  author = {Giacomin, Valeria and Lutz, Chandler},
  title = {{Historical London Company Geocoding Pipeline (Early 20th Century)}},
  year = {2025},
  url = {https://github.com/ChandlerLutz/plantation-lse-london-geolocation},
  note = {GitHub repository}
}
```
