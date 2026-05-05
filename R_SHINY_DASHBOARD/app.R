
# =============================================================================
# LIVESTOCK INTELLIGENCE - R SHINY DASHBOARD
# Kelompok 1 TPD (3SI1) - POLSTAT STIS
# Integrated OLAP Analysis Dashboard
# =============================================================================

library(shiny)
library(shinydashboard)
library(shinyWidgets)
library(tidyverse)
library(plotly)
library(DT)
library(sf)
library(leaflet)
library(RPostgres)
library(DBI)
library(pool)
library(scales)
library(gridExtra)
library(lubridate)
library(corpcor)

# Load configuration
source('config.R')
source('ui_components.R')
source('server_logic.R')

# =============================================================================
# MAIN SHINY APP
# =============================================================================

ui <- dashboardPage(
  skin = "blue",
  
  dashboardHeader(
    title = HTML(
      '<div style="padding: 5px; font-weight: bold;">
        <img src="logo.png" height="30" style="margin-right: 10px;">
        LIVESTOCK INTELLIGENCE
      </div>'
    ),
    titleWidth = 400,
    tags$li(
      class = "dropdown",
      HTML(
        '<a href="#" class="dropdown-toggle" data-toggle="dropdown" style="color: white; margin-right: 20px;">
          <i class="fa fa-bell"></i> <span class="badge bg-red" id="alert_count">0</span>
        </a>'
      )
    )
  ),
  
  dashboardSidebar(
    width = 280,
    sidebarMenu(
      id = "sidebarmenu",
      
      menuItem(
        "Executive Summary",
        tabName = "tab_executive",
        icon = icon("gauge-high")
      ),
      
      menuItem(
        "OLAP Analytics",
        icon = icon("chart-line"),
        menuSubItem("Early Warning System", tabName = "tab_early_warning"),
        menuSubItem("Price vs Disease", tabName = "tab_price_disease"),
        menuSubItem("Supply-Demand Gap", tabName = "tab_gap_analysis"),
        menuSubItem("Spatial Risk Map", tabName = "tab_spatial_risk"),
        menuSubItem("Supply Dependency", tabName = "tab_supply_dep")
      ),
      
      menuItem(
        "Data Explorer",
        tabName = "tab_explorer",
        icon = icon("database")
      ),
      
      menuItem(
        "Documentation",
        tabName = "tab_docs",
        icon = icon("book")
      ),
      
      hr(),
      
      # FILTER PANEL
      h4("OLAP Filters", style = "color: #0066cc; font-weight: bold; margin-top: 20px;"),
      
      pickerInput(
        inputId = "filter_province",
        label = "Provinsi (Slicing)",
        choices = NULL,
        multiple = TRUE,
        options = pickerOptions(
          actionsBox = TRUE,
          title = "Pilih Provinsi"
        ),
        selected = NULL
      ),
      
      radioButtons(
        inputId = "filter_commodity",
        label = "Komoditas (Dicing)",
        choiceNames = c("Sapi", "Ayam", "Semua"),
        choiceValues = c("Sapi", "Ayam", "ALL"),
        selected = "ALL"
      ),
      
      sliderInput(
        inputId = "filter_year",
        label = "Tahun (Dicing)",
        min = 2020,
        max = 2025,
        value = c(2023, 2025),
        step = 1,
        sep = ""
      ),
      
      checkboxGroupInput(
        inputId = "filter_quarter",
        label = "Kuartal (Dicing)",
        choiceNames = c("Q1 (Jan-Mar)", "Q2 (Apr-Jun)", "Q3 (Jul-Sep)", "Q4 (Oct-Dec)"),
        choiceValues = c("Q1", "Q2", "Q3", "Q4"),
        selected = c("Q1", "Q2", "Q3", "Q4")
      ),
      
      hr(),
      
      actionButton(
        "btn_apply_filters",
        "Apply Filters (Query)",
        icon = icon("play"),
        class = "btn-primary btn-block"
      ),
      
      actionButton(
        "btn_reset_filters",
        "Reset",
        icon = icon("rotate-left"),
        class = "btn-secondary btn-block"
      )
    )
  ),
  
  dashboardBody(
    
    # Custom CSS
    tags$head(
      tags$style(HTML("
        .content-header { background-color: #f4f4f4; padding: 15px; border-radius: 5px; }
        .metric-box { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
                      color: white; padding: 20px; border-radius: 8px; 
                      box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .metric-value { font-size: 32px; font-weight: bold; }
        .metric-label { font-size: 14px; opacity: 0.9; margin-top: 5px; }
        .card-header { background-color: #0066cc; color: white; padding: 12px; 
                       font-weight: bold; border-radius: 5px 5px 0 0; }
        .alert-critical { background-color: #dc3545; }
        .alert-warning { background-color: #ffc107; }
        .alert-info { background-color: #17a2b8; }
        .olap-level { background-color: #e7f3ff; padding: 10px; border-left: 4px solid #0066cc; margin: 10px 0; }
      "))
    ),
    
    tabItems(
      
      # =========================================================================
      # TAB 1: EXECUTIVE SUMMARY
      # =========================================================================
      tabItem(
        tabName = "tab_executive",
        
        h2("Executive Summary - Current Status", style = "color: #0066cc; font-weight: bold;"),
        p("Ringkasan Indikator Kunci & Alert Status Terakhir", style = "color: #666; font-style: italic;"),
        
        br(),
        
        # KPI Boxes
        fluidRow(
          column(
            3,
            div(
              class = "metric-box",
              style = "background: linear-gradient(135deg, #FF6B6B 0%, #FF4757 100%);",
              div(class = "metric-value", textOutput("kpi_critical_provs")),
              div(class = "metric-label", "Provinsi Status CRITICAL")
            )
          ),
          column(
            3,
            div(
              class = "metric-box",
              style = "background: linear-gradient(135deg, #FFA502 0%, #FF7675 100%);",
              div(class = "metric-value", textOutput("kpi_warning_provs")),
              div(class = "metric-label", "Provinsi Status WARNING")
            )
          ),
          column(
            3,
            div(
              class = "metric-box",
              style = "background: linear-gradient(135deg, #74B9FF 0%, #0984E3 100%);",
              div(class = "metric-value", textOutput("kpi_avg_risk")),
              div(class = "metric-label", "Avg Risk Index (National)")
            )
          ),
          column(
            3,
            div(
              class = "metric-box",
              style = "background: linear-gradient(135deg, #6C5CE7 0%, #A29BFE 100%);",
              div(class = "metric-value", textOutput("kpi_deficit_regions")),
              div(class = "metric-label", "Wilayah Deficit Supply")
            )
          )
        ),
        
        br(),
        
        # Current Alert Table
        h3("Current Alert Status (Latest Month)", style = "color: #0066cc; font-weight: bold;"),
        p("OLAP Roll-Up: Agregasi ke Provinsi Level", style = "color: #666; font-style: italic;"),
        
        DT::dataTableOutput("table_current_alerts"),
        
        br(),
        
        # National Trends
        fluidRow(
          column(
            6,
            div(
              class = "card-header",
              "National Trend: Risk Index Over Time"
            ),
            plotlyOutput("plot_national_trend", height = 350)
          ),
          column(
            6,
            div(
              class = "card-header",
              "Risk Zone Distribution"
            ),
            plotlyOutput("plot_risk_zones", height = 350)
          )
        )
      ),
      
      # =========================================================================
      # TAB 2: EARLY WARNING SYSTEM
      # =========================================================================
      tabItem(
        tabName = "tab_early_warning",
        
        h2("Early Warning System", style = "color: #0066cc; font-weight: bold;"),
        p("Supply Risk Index = (Price Gap + Health Impact + Supply Strain) / 3, 
          dengan Min-Max Scaling [0-1]", 
          style = "color: #666; font-style: italic;"),
        
        br(),
        
        div(
          class = "olap-level",
          HTML(
            "<b>OLAP Operations:</b> <br/>
             • <b>SLICING:</b> Filter by Provinsi | <b>DICING:</b> Filter by Komoditas, Tahun, Kuartal<br/>
             • <b>ROLL-UP:</b> Agregasi ke Provinsi-Komoditas Level | <b>DRILL-DOWN:</b> Detail Bulanan"
          )
        ),
        
        br(),
        
        # Top Risk Provinces
        fluidRow(
          column(
            6,
            div(
              class = "card-header",
              "Top 10 Provinsi Risk Tertinggi (Roll-up)"
            ),
            plotlyOutput("plot_top_risk_provs", height = 400)
          ),
          column(
            6,
            div(
              class = "card-header",
              "Risk Timeline: Top 5 Berisiko (Drill-down)"
            ),
            plotlyOutput("plot_risk_timeline", height = 400)
          )
        ),
        
        br(),
        
        # Risk Component Analysis
        fluidRow(
          column(
            12,
            div(
              class = "card-header",
              "Risk Index Components Analysis (Latest Period)"
            ),
            plotlyOutput("plot_risk_components", height = 350)
          )
        ),
        
        br(),
        
        # Detailed Risk Table (Drill-down)
        h3("Detailed Risk Assessment (Drill-down: Monthly Level)", style = "color: #0066cc;"),
        DT::dataTableOutput("table_detailed_risk")
      ),
      
      # =========================================================================
      # TAB 3: PRICE VS DISEASE CORRELATION
      # =========================================================================
      tabItem(
        tabName = "tab_price_disease",
        
        h2("Price-Disease Correlation Analysis", style = "color: #0066cc; font-weight: bold;"),
        p("Membuktikan apakah volatilitas harga disebabkan oleh wabah atau faktor lain (OLAP DICING & DRILL-DOWN)",
          style = "color: #666; font-style: italic;"),
        
        br(),
        
        div(
          class = "olap-level",
          HTML(
            "<b>OLAP Operations:</b> <br/>
             • <b>DICING:</b> Filter by Komoditas | <b>DRILL-DOWN:</b> Time Series Detail<br/>
             • Pearson Correlation dengan Significance Test (p-value < 0.05)"
          )
        ),
        
        br(),
        
        # Correlation Summary
        fluidRow(
          column(
            12,
            div(
              class = "card-header",
              "Pearson Correlation: Harga vs Jumlah Sakit (Dicing by Commodity)"
            ),
            DT::dataTableOutput("table_correlation_summary")
          )
        ),
        
        br(),
        
        # Time Series Comparison
        fluidRow(
          column(
            6,
            div(
              class = "card-header",
              "Dual-Axis Time Series: Sapi"
            ),
            plotlyOutput("plot_timeseries_sapi", height = 400)
          ),
          column(
            6,
            div(
              class = "card-header",
              "Dual-Axis Time Series: Ayam"
            ),
            plotlyOutput("plot_timeseries_ayam", height = 400)
          )
        ),
        
        br(),
        
        # Scatter Plot with Regression
        fluidRow(
          column(
            6,
            div(
              class = "card-header",
              "Scatter & Regression: Sapi"
            ),
            plotlyOutput("plot_scatter_sapi", height = 350)
          ),
          column(
            6,
            div(
              class = "card-header",
              "Scatter & Regression: Ayam"
            ),
            plotlyOutput("plot_scatter_ayam", height = 350)
          )
        ),
        
        br(),
        
        # Interpretation Box
        div(
          class = "alert alert-info",
          h4("Interpretasi Korelasi:", style = "margin-top: 0;"),
          htmlOutput("text_correlation_interpretation")
        )
      ),
      
      # =========================================================================
      # TAB 4: SUPPLY VS DEMAND GAP
      # =========================================================================
      tabItem(
        tabName = "tab_gap_analysis",
        
        h2("Supply vs Demand Gap Analysis", style = "color: #0066cc; font-weight: bold;"),
        p("Mengukur ketimpangan antara permintaan (BPS) dan realisasi pengiriman (iSIKHNAS) - Level Logistik & Konsumsi",
          style = "color: #666; font-style: italic;"),
        
        br(),
        
        div(
          class = "olap-level",
          HTML(
            "<b>OLAP Operations:</b> <br/>
             • <b>SLICING:</b> Filter Provinsi | <b>DICING:</b> Filter Komoditas<br/>
             • <b>ROLL-UP:</b> Agregasi ke Nasional | <b>DRILL-DOWN:</b> Detail Provinsi & Bulan"
          )
        ),
        
        br(),
        
        # Gap Summary by Commodity
        fluidRow(
          column(
            12,
            div(
              class = "card-header",
              "Gap Summary Statistics (Roll-up: Nasional)"
            ),
            DT::dataTableOutput("table_gap_summary")
          )
        ),
        
        br(),
        
        # Gap Timeline
        fluidRow(
          column(
            12,
            div(
              class = "card-header",
              "Supply-Demand Gap Timeline (Drill-down: Bulanan)"
            ),
            plotlyOutput("plot_gap_timeline", height = 400)
          )
        ),
        
        br(),
        
        # Provincial Deficits
        fluidRow(
          column(
            6,
            div(
              class = "card-header",
              "Top 10 Provinsi DEFICIT (Level Logistik)"
            ),
            plotlyOutput("plot_deficit_provinces", height = 350)
          ),
          column(
            6,
            div(
              class = "card-header",
              "Gap Distribution by Province (Box Plot)"
            ),
            plotlyOutput("plot_gap_distribution", height = 350)
          )
        ),
        
        br(),
        
        # Detailed Gap Table
        h3("Detailed Gap Analysis (Drill-down: Provinsi & Bulanan)", style = "color: #0066cc;"),
        DT::dataTableOutput("table_detailed_gap")
      ),
      
      # =========================================================================
      # TAB 5: SPATIAL RISK MAP
      # =========================================================================
      tabItem(
        tabName = "tab_spatial_risk",
        
        h2("Spatial Risk Mapping", style = "color: #0066cc; font-weight: bold;"),
        p("Memetakan risiko pasokan berdasarkan populasi ternak, densitas penyakit, dan supply risk index (ROLL-UP Spasial)",
          style = "color: #666; font-style: italic;"),
        
        br(),
        
        div(
          class = "olap-level",
          HTML(
            "<b>OLAP Operations:</b> <br/>
             • <b>SLICING:</b> Filter Komoditas | <b>ROLL-UP:</b> Agregasi ke Provinsi Level<br/>
             • Spatial Join: Shapefile ADMINISTRAS_PROVINSI → Dimensi Provinsi (by nama_provinsi)"
          )
        ),
        
        br(),
        
        # Spatial Map
        fluidRow(
          column(
            12,
            div(
              class = "card-header",
              "Interactive Choropleth Map - Supply Risk Index"
            ),
            leafletOutput("map_spatial_risk", height = 550)
          )
        ),
        
        br(),
        
        # Risk Zone Distribution
        fluidRow(
          column(
            6,
            div(
              class = "card-header",
              "Risk Zone Classification"
            ),
            plotlyOutput("plot_zone_distribution", height = 350)
          ),
          column(
            6,
            div(
              class = "card-header",
              "Bubble Chart: Population vs Disease Density vs Risk"
            ),
            plotlyOutput("plot_risk_bubble", height = 350)
          )
        ),
        
        br(),
        
        # Spatial Risk Table
        h3("Spatial Risk Matrix (ROLL-UP: Provinsi)", style = "color: #0066cc;"),
        p("Ranking by Supply Risk Index dengan Rekomendasi Intervensi", style = "color: #666;"),
        DT::dataTableOutput("table_spatial_risk")
      ),
      
      # =========================================================================
      # TAB 6: SUPPLY DEPENDENCY
      # =========================================================================
      tabItem(
        tabName = "tab_supply_dep",
        
        h2("Supply Dependency & Concentration", style = "color: #0066cc; font-weight: bold;"),
        p("Menganalisis ketergantungan wilayah konsumen (Jabodetabek) pada wilayah produsen - Pareto & Concentration Analysis",
          style = "color: #666; font-style: italic;"),
        
        br(),
        
        div(
          class = "olap-level",
          HTML(
            "<b>OLAP Operations:</b> <br/>
             • <b>SLICING:</b> Filter Komoditas & Provinsi Tujuan | <b>ROLL-UP:</b> Agregasi Nasional<br/>
             • Analisis Dependensi: Proporsi Supply per Provinsi Asal"
          )
        ),
        
        br(),
        
        # Dependency Summary
        fluidRow(
          column(
            12,
            div(
              class = "card-header",
              "Supply Concentration: Top Suppliers untuk Jabodetabek"
            ),
            DT::dataTableOutput("table_dependency_summary")
          )
        ),
        
        br(),
        
        # Pareto Analysis
        fluidRow(
          column(
            6,
            div(
              class = "card-header",
              "Pareto Chart: Supply Concentration (Sapi)"
            ),
            plotlyOutput("plot_pareto_sapi", height = 400)
          ),
          column(
            6,
            div(
              class = "card-header",
              "Pareto Chart: Supply Concentration (Ayam)"
            ),
            plotlyOutput("plot_pareto_ayam", height = 400)
          )
        ),
        
        br(),
        
        # Vulnerability Assessment
        h3("Vulnerability Assessment: Key Supplier Risk", style = "color: #0066cc;"),
        p("Identifikasi supplier utama dengan risk index tinggi → potential crisis trigger", style = "color: #666;"),
        div(
          class = "alert alert-danger",
          htmlOutput("text_vulnerability_assessment")
        )
      ),
      
      # =========================================================================
      # TAB 7: DATA EXPLORER
      # =========================================================================
      tabItem(
        tabName = "tab_explorer",
        
        h2("Data Explorer", style = "color: #0066cc; font-weight: bold;"),
        p("Explore raw OLAP cube data dengan custom filtering dan export capabilities",
          style = "color: #666; font-style: italic;"),
        
        br(),
        
        # Export Buttons
        fluidRow(
          column(
            12,
            downloadButton("btn_download_csv", "Download as CSV", class = "btn-primary"),
            downloadButton("btn_download_xlsx", "Download as Excel", class = "btn-success"),
            downloadButton("btn_download_pdf", "Download as PDF", class = "btn-danger"),
            style = "margin-bottom: 15px;"
          )
        ),
        
        # Data Table
        DT::dataTableOutput("table_explorer", height = 600)
      ),
      
      # =========================================================================
      # TAB 8: DOCUMENTATION
      # =========================================================================
      tabItem(
        tabName = "tab_docs",
        
        h2("Documentation & Technical Guide", style = "color: #0066cc; font-weight: bold;"),
        
        br(),
        
        tabsetPanel(
          tabPanel(
            "OLAP Concepts",
            br(),
            h3("OLAP Operations dalam Dashboard"),
            HTML("
              <h4>1. SLICING</h4>
              <p>Filter data pada satu dimensi. Contoh: Pilih hanya Provinsi Jawa Timur.</p>
              
              <h4>2. DICING</h4>
              <p>Filter data pada multiple dimensi. Contoh: Sapi + Jawa Timur + 2024 + Q1.</p>
              
              <h4>3. ROLL-UP</h4>
              <p>Agregasi data ke level lebih tinggi. Contoh: Detail Bulan → Agregasi Tahun/Nasional.</p>
              
              <h4>4. DRILL-DOWN</h4>
              <p>Disagregasi ke level lebih detail. Contoh: Nasional → Detail Provinsi → Detail Bulan.</p>
              
              <h4>5. PIVOT</h4>
              <p>Ubah orientasi data. Contoh: Baris = Provinsi, Kolom = Bulan.</p>
            ")
          ),
          
          tabPanel(
            "Metrics Definition",
            br(),
            h3("Key Metrics Definitions"),
            HTML("
              <table class='table table-bordered'>
                <tr>
                  <th>Metrik</th>
                  <th>Definisi</th>
                  <th>Sumber</th>
                </tr>
                <tr>
                  <td><b>supply_risk_index</b></td>
                  <td>Agregasi dari Price Gap, Health Impact, Supply Strain dengan Min-Max Scaling [0-1]</td>
                  <td>Computed</td>
                </tr>
                <tr>
                  <td><b>avg_harga</b></td>
                  <td>Rata-rata harga pasar (Rp) aggregated across pasar tradisional, modern, pedagang besar</td>
                  <td>PIHPS</td>
                </tr>
                <tr>
                  <td><b>sum_jumlah_sakit</b></td>
                  <td>Total kasus penyakit ternak (gejala) dalam periode</td>
                  <td>iSIKHNAS</td>
                </tr>
                <tr>
                  <td><b>sum_vol_mutasi</b></td>
                  <td>Total volume pengiriman ternak antar provinsi (ekor)</td>
                  <td>iSIKHNAS</td>
                </tr>
                <tr>
                  <td><b>sum_realisasi_karkas</b></td>
                  <td>Total berat karkas hasil pemotongan (Kg)</td>
                  <td>iSIKHNAS</td>
                </tr>
                <tr>
                  <td><b>populasi_ternak</b></td>
                  <td>Populasi ternak (ekor) dari data BPS</td>
                  <td>BPS</td>
                </tr>
              </table>
            ")
          ),
          
          tabPanel(
            "Filter Logic",
            br(),
            h3("Understanding Filter Logic"),
            HTML("
              <p><b>SAAT FILTERS DITERAPKAN:</b></p>
              <ul>
                <li><b>Provinsi:</b> Jika kosong = semua provinsi; jika dipilih = filter ke provinsi terpilih (SLICING)</li>
                <li><b>Komoditas:</b> Filter ke Sapi/Ayam/Semua (DICING)</li>
                <li><b>Tahun:</b> Range slider untuk pemilihan tahun (DICING temporal)</li>
                <li><b>Kuartal:</b> Multi-select untuk Q1-Q4 (DICING temporal)</li>
              </ul>
              <p><b>Kombinasi filters = DICING (multi-dimensional filtering)</b></p>
            ")
          ),
          
          tabPanel(
            "Data Sources",
            br(),
            h3("Data Integration Overview"),
            HTML("
              <h4>BPS (Badan Pusat Statistik)</h4>
              <p>• Populasi wilayah (jiwa)<br/>
                 • Populasi ternak (ekor)<br/>
                 • Produksi daging (Kg/ton)</p>
              
              <h4>iSIKHNAS (Sistem Informasi Kesehatan Hewan)</h4>
              <p>• Mutasi ternak antar provinsi<br/>
                 • Laporan penyakit & kematian ternak<br/>
                 • Data pemotongan di RPH</p>
              
              <h4>PIHPS (Sistem Harga Pangan Strategis)</h4>
              <p>• Harga daging di pasar tradisional/modern<br/>
                 • Harga pedagang besar</p>
              
              <h4>Shapefile</h4>
              <p>• ADMINISTRAS_PROVINSI.shp untuk spatial mapping</p>
            ")
          )
        )
      )
    )
  )
)

server <- function(input, output, session) {
  source('server_reactive.R', local = TRUE)
}

shinyApp(ui, server)
