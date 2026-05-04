# ==============================================================================
# LIVESTOCK INTELLIGENCE - R SHINY DASHBOARD
# app.R: Main Application Entry Point
# ==============================================================================

# Load global environment (database connection, utility functions, libraries)
source("global.R")

# Load UI layout
source("ui.R")

# Load server logic
source("server.R")

# Run the Shiny application
shinyApp(ui = ui, server = server)
