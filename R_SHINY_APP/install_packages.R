# ==============================================================================
# LIVESTOCK INTELLIGENCE - R Package Installation Script
# Run this script once to install all required dependencies
# ==============================================================================

cat("Installing Livestock Intelligence Dashboard Dependencies...\n")
cat("=" * 70, "\n\n")

# List of required packages
packages <- c(
  # Shiny & UI
  "shiny",
  "shinydashboard",
  "shinyWidgets",
  "shinyalert",
  
  # Database & Data Manipulation
  "DBI",
  "RPostgres",
  "dplyr",
  "dbplyr",
  "tidyr",
  
  # Spatial Data & Mapping
  "sf",
  "leaflet",
  "leaflet.extras",
  
  # Visualization
  "plotly",
  "ggplot2",
  "scales",
  "treemapify",
  
  # Data Processing & Statistics
  "tidyverse",
  "lubridate",
  "zoo",
  "corrplot",
  
  # Data Tables
  "DT",
  
  # Utilities
  "formattable"
)

# Function to safely install package
install_if_needed <- function(pkg) {
  if (!require(pkg, character.only = TRUE)) {
    cat(sprintf("Installing %s...\n", pkg))
    install.packages(pkg, dependencies = TRUE)
    
    if (require(pkg, character.only = TRUE)) {
      cat(sprintf("✓ %s installed successfully\n", pkg))
    } else {
      cat(sprintf("✗ Failed to install %s\n", pkg))
      return(FALSE)
    }
  } else {
    cat(sprintf("✓ %s already installed\n", pkg))
  }
  return(TRUE)
}

# Install all packages
success_count <- 0
for (pkg in packages) {
  if (install_if_needed(pkg)) {
    success_count <- success_count + 1
  }
}

cat("\n" * 70, "\n")
cat(sprintf("Installation Summary: %d/%d packages successfully installed\n", 
            success_count, length(packages)))

if (success_count == length(packages)) {
  cat("\n✓ All dependencies installed successfully!\n")
  cat("You can now run the dashboard with: shiny::runApp()\n")
} else {
  cat("\n✗ Some packages failed to install. Please check error messages above.\n")
  cat("You may need to install system dependencies or check your internet connection.\n")
}
