# ==============================================================================
# LIVESTOCK INTELLIGENCE - R SHINY DASHBOARD
# ui.R: User Interface Layout (3 Tabs with Sidebar Filters)
# ==============================================================================

dashboardPage(
  
  # ============================================================================
  # DASHBOARD HEADER
  # ============================================================================
  dashboardHeader(
    title = "Livestock Intelligence",
    titleWidth = 300,
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "custom.css"),
      tags$script(src = "custom.js")
    ),
    # Header info box
    dropdownMenu(
      type = "messages",
      messageItem(
        from = "System",
        message = "Real-time Data Warehouse Integration",
        icon = icon("database"),
        time = Sys.time()
      )
    )
  ),
  
  # ============================================================================
  # LEFT SIDEBAR - FILTERS & CONTROLS
  # ============================================================================
  dashboardSidebar(
    width = 280,
    
    # Sidebar Menu
    sidebarMenu(
      id = "sidebar_menu",
      
      menuItem(
        "Executive Summary (Alarm)",
        tabName = "tab_alarm",
        icon = icon("bell")
      ),
      menuItem(
        "Analisis Sektor Riil",
        tabName = "tab_supply_demand",
        icon = icon("chart-bar")
      ),
      menuItem(
        "Investigasi & Korelasi",
        tabName = "tab_investigation",
        icon = icon("microscope")
      ),
      
      # Divider
      hr(),
      
      # =====================================================================
      # FILTER CONTROLS (OLAP Slicing & Dicing)
      # =====================================================================
      
      tags$h4("Filter Data", style = "margin-top: 20px; padding: 0 15px;"),
      
      # FILTER 1: Pilih Provinsi (SLICING)
      selectInput(
        inputId = "filter_provinsi",
        label = "Provinsi:",
        choices = prov_list,
        selected = "Nasional",
        width = "100%"
      ),
      
      # FILTER 2: Pilih Komoditas (SLICING)
      radioButtons(
        inputId = "filter_komoditas",
        label = "Komoditas:",
        choices = komoditas_list,
        selected = "Sapi",
        inline = FALSE
      ),
      
      # FILTER 3: Tahun Range (DICING)
      sliderInput(
        inputId = "filter_tahun",
        label = "Rentang Tahun:",
        min = min_year,
        max = max_year,
        value = c(min_year, max_year),
        step = 1,
        sep = ""
      ),
      
      # FILTER 4: Pilih Bulan (DICING)
      checkboxGroupInput(
        inputId = "filter_bulan",
        label = "Bulan:",
        choices = list(
          "Jan" = 1, "Feb" = 2, "Mar" = 3, "Apr" = 4,
          "May" = 5, "Jun" = 6, "Jul" = 7, "Aug" = 8,
          "Sep" = 9, "Oct" = 10, "Nov" = 11, "Dec" = 12
        ),
        selected = 1:12,
        inline = TRUE
      ),
      
      # Apply Button
      actionButton(
        inputId = "btn_apply_filter",
        label = "Apply Filters",
        class = "btn btn-primary btn-block",
        style = "margin-top: 15px; margin-bottom: 15px;"
      ),
      
      hr(),
      
      # =====================================================================
      # DATA EXPORT & HELP
      # =====================================================================
      
      tags$h5("Export & Help", style = "padding: 0 15px;"),
      
      downloadButton(
        outputId = "download_data",
        label = "Download Data",
        class = "btn btn-sm btn-info",
        style = "width: 100%; margin-bottom: 10px;"
      ),
      
      actionButton(
        inputId = "btn_help",
        label = "Bantuan",
        class = "btn btn-sm btn-default",
        style = "width: 100%;"
      )
    )
  ),
  
  # ============================================================================
  # MAIN CONTENT AREA - TAB PANELS
  # ============================================================================
  dashboardBody(
    
    # Custom CSS for styling
    tags$head(
      tags$style(HTML("
        .box-title {
          font-weight: bold;
          font-size: 16px;
        }
        .info-box-number {
          font-size: 32px;
          font-weight: bold;
        }
        .gauge-container {
          text-align: center;
          padding: 20px;
        }
        .risk-low {
          color: #2ecc71;
          font-weight: bold;
        }
        .risk-medium {
          color: #f39c12;
          font-weight: bold;
        }
        .risk-high {
          color: #e74c3c;
          font-weight: bold;
        }
        .alert-box {
          padding: 15px;
          margin: 15px 0;
          border-radius: 4px;
          border-left: 4px solid #e74c3c;
          background-color: #fadbd8;
        }
        .timeline-item {
          padding: 15px 0;
          border-bottom: 1px solid #ecf0f1;
        }
      "))
    ),
    
    tabsetPanel(
      type = "tabs",
      id = "main_tabs",
      
      # =====================================================================
      # TAB 1: EXECUTIVE SUMMARY (THE ALARM) - EARLY WARNING SYSTEM
      # =====================================================================
      tabPanel(
        title = "Executive Summary",
        value = "tab_alarm",
        
        # Row 1: National KPIs
        fluidRow(
          box(
            title = "National Supply Risk Index",
            status = "warning",
            solidHeader = TRUE,
            width = 3,
            height = 150,
            
            # Main gauge display
            div(
              class = "gauge-container",
              textOutput("kpi_national_risk") %>%
                tagAppendAttributes(style = "font-size: 48px; font-weight: bold;")
            )
          ),
          
          box(
            title = "Average Price (IDR/kg)",
            status = "info",
            solidHeader = TRUE,
            width = 3,
            height = 150,
            
            div(
              class = "gauge-container",
              textOutput("kpi_national_price") %>%
                tagAppendAttributes(style = "font-size: 48px; font-weight: bold;")
            )
          ),
          
          box(
            title = "Total Disease Reports",
            status = "danger",
            solidHeader = TRUE,
            width = 3,
            height = 150,
            
            div(
              class = "gauge-container",
              textOutput("kpi_total_sick") %>%
                tagAppendAttributes(style = "font-size: 48px; font-weight: bold;")
            )
          ),
          
          box(
            title = "Supply Volume (Ekor)",
            status = "success",
            solidHeader = TRUE,
            width = 3,
            height = 150,
            
            div(
              class = "gauge-container",
              textOutput("kpi_supply_volume") %>%
                tagAppendAttributes(style = "font-size: 48px; font-weight: bold;")
            )
          )
        ),
        
        # Row 2: Alert notification
        fluidRow(
          box(
            title = "⚠️ Peringatan Sistem",
            status = "danger",
            solidHeader = TRUE,
            width = 12,
            collapsible = TRUE,
            collapsed = FALSE,
            
            textOutput("alert_high_dependency") %>%
              tagAppendAttributes(class = "alert-box")
          )
        ),
        
        # Row 3: Top Risk Provinces (Slicing visualization)
        fluidRow(
          box(
            title = "Top 5 Provinsi dengan Risiko Pasokan Tertinggi",
            status = "danger",
            solidHeader = TRUE,
            width = 6,
            height = 400,
            
            plotlyOutput("chart_top_provinces")
          ),
          
          box(
            title = "Distribusi Risiko Pasokan",
            status = "warning",
            solidHeader = TRUE,
            width = 6,
            height = 400,
            
            tableOutput("table_top_provinces")
          )
        ),
        
        # Row 4: Spatial Choropleth Map (Spatial OLAP)
        fluidRow(
          box(
            title = "Peta Risiko Spasial - Kerentanan Wilayah",
            status = "primary",
            solidHeader = TRUE,
            width = 12,
            height = 600,
            collapsible = TRUE,
            
            leafletOutput("choropleth_map", height = 550)
          )
        )
      ),
      
      # =====================================================================
      # TAB 2: ANALISIS SEKTOR RIIL
      # (Supply vs Demand Gap, Dependency Analysis)
      # =====================================================================
      tabPanel(
        title = "Analisis Sektor Riil",
        value = "tab_supply_demand",
        
        # Row 1: Supply vs Demand Gap (Logistik Level)
        fluidRow(
          box(
            title = "Analisis Kesenjangan Pasokan - Level Logistik (Ekor)",
            status = "info",
            solidHeader = TRUE,
            width = 6,
            height = 400,
            
            plotlyOutput("chart_supply_demand_ekor")
          ),
          
          box(
            title = "Analisis Kesenjangan Pasokan - Level Konsumsi (Kg)",
            status = "success",
            solidHeader = TRUE,
            width = 6,
            height = 400,
            
            plotlyOutput("chart_supply_demand_kg")
          )
        ),
        
        # Row 2: Gap Analysis Summary Table
        fluidRow(
          box(
            title = "Summary: Supply-Demand Gap",
            status = "warning",
            solidHeader = TRUE,
            width = 12,
            
            tableOutput("table_supply_demand_gap")
          )
        ),
        
        # Row 3: Supply Dependency (Concentration)
        fluidRow(
          box(
            title = "Ketergantungan Pasokan - % Kontribusi Provinsi Terhadap Nasional",
            status = "danger",
            solidHeader = TRUE,
            width = 6,
            height = 450,
            
            plotlyOutput("chart_dependency_treemap")
          ),
          
          box(
            title = "Detail Ketergantungan Supply",
            status = "warning",
            solidHeader = TRUE,
            width = 6,
            height = 450,
            
            tableOutput("table_dependency_detail")
          )
        ),
        
        # Row 4: Critical Dependency Alert
        fluidRow(
          box(
            title = "⚠️ Alert: Ketergantungan Kritis",
            status = "danger",
            solidHeader = TRUE,
            width = 12,
            collapsible = TRUE,
            
            htmlOutput("alert_critical_dependency")
          )
        )
      ),
      
      # =====================================================================
      # TAB 3: INVESTIGASI & KORELASI
      # (Time Series: Price vs Disease, Correlation Analysis)
      # =====================================================================
      tabPanel(
        title = "Investigasi & Korelasi",
        value = "tab_investigation",
        
        # Row 1: Dual-Axis Time Series (Price vs Disease)
        fluidRow(
          box(
            title = "Tren Harga vs Wabah (Time Series Analisis)",
            status = "primary",
            solidHeader = TRUE,
            width = 12,
            height = 500,
            collapsible = FALSE,
            
            plotlyOutput("chart_price_disease_timeseries", height = 450)
          )
        ),
        
        # Row 2: Correlation Coefficient & Interpretation
        fluidRow(
          box(
            title = "Analisis Korelasi: Harga ↔ Penyakit",
            status = "info",
            solidHeader = TRUE,
            width = 6,
            height = 300,
            
            div(
              style = "padding: 20px; text-align: center;",
              h3(textOutput("corr_coefficient"), style = "font-size: 48px; margin: 10px 0;"),
              p("Koefisien Korelasi Pearson"),
              hr(),
              htmlOutput("corr_interpretation")
            )
          ),
          
          box(
            title = "Scatter Plot: Harga vs Penyakit",
            status = "warning",
            solidHeader = TRUE,
            width = 6,
            height = 300,
            
            plotlyOutput("chart_price_disease_scatter")
          )
        ),
        
        # Row 3: Correlation Matrix (All Metrics)
        fluidRow(
          box(
            title = "Correlation Matrix - Semua Metrik Kunci",
            status = "info",
            solidHeader = TRUE,
            width = 12,
            height = 450,
            collapsible = TRUE,
            
            plotOutput("chart_correlation_matrix", height = 400)
          )
        ),
        
        # Row 4: Detailed Data Table
        fluidRow(
          box(
            title = "Data Detail - Tren Bulanan",
            status = "primary",
            solidHeader = TRUE,
            width = 12,
            
            dataTableOutput("table_investigation_detail")
          )
        )
      )
    )
  )
)
