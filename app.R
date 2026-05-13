suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(tidyverse)
  library(ggplot2)
  library(patchwork)
  library(DT)
  library(TTR)
  library(forcats)
})

source("R/processing.R")
source("R/plotting.R")

# ── UI ──────────────────────────────────────────────────────────────────────

ui <- page_sidebar(
  title = "MSstats HYE Combined Plots Generator",
  theme = bs_theme(bootswatch = "flatly", primary = "#2c7bb6"),

  sidebar = sidebar(
    width = 320,

    # Step 1 ─ upload
    card(
      card_header("1  Upload Spectronaut Report", class = "bg-primary text-white fw-bold"),
      fileInput("input_file", NULL,
                accept      = c(".tsv", ".csv"),
                buttonLabel = "Browse…",
                placeholder = "TSV or CSV"),
      radioButtons("data_level", "Quantification level",
                   choices  = c("Precursor (MS1)" = "precursor",
                                "Fragment (MS2)"  = "fragment"),
                   selected = "precursor",
                   inline   = TRUE)
    ),

    # Step 2 ─ conditions
    card(
      card_header("2  Assign Mix Conditions", class = "bg-primary text-white fw-bold"),
      uiOutput("condition_ui"),
      helpText("Upload a file to detect conditions.")
    ),

    # Step 3 ─ parameters
    card(
      card_header("3  Analysis Parameters", class = "bg-primary text-white fw-bold"),
      layout_columns(
        col_widths = c(4, 4, 4),
        numericInput("ratio_H", "H",     value = 1,    min = 0.01, step = 0.1),
        numericInput("ratio_E", "E",     value = 0.25, min = 0.01, step = 0.05),
        numericInput("ratio_Y", "Y",     value = 2,    min = 0.01, step = 0.1)
      ),
      helpText("Expected MixA / MixB ratios: H = HeLa, E = E. coli, Y = Yeast"),
      layout_columns(
        col_widths = c(6, 6),
        numericInput("n_replicates", "Replicates",  value = 4,   min = 2, max = 12),
        numericInput("sma_window",   "SMA window",  value = 150, min = 10, max = 500)
      )
    ),

    actionButton("run_btn", "Generate Plots",
                 icon  = icon("chart-bar"),
                 class = "btn-primary w-100 mt-1"),

    uiOutput("download_panel")
  ),

  # Main area
  uiOutput("main_panel")
)

# ── Server ───────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  # ── Read file ──────────────────────────────────────────────────────────────
  raw_data <- reactive({
    req(input$input_file)
    ext <- tolower(tools::file_ext(input$input_file$name))
    sep <- if (ext == "csv") "," else "\t"
    tryCatch(
      read_delim(input$input_file$datapath, delim = sep, show_col_types = FALSE),
      error = function(e) {
        showNotification(paste("Read error:", e$message), type = "error", duration = 10)
        NULL
      }
    )
  })

  conditions <- reactive({
    req(raw_data())
    if (!"R.Condition" %in% colnames(raw_data())) return(character(0))
    sort(unique(as.character(raw_data()$R.Condition)))
  })

  output$condition_ui <- renderUI({
    conds <- conditions()
    if (length(conds) == 0) return(NULL)
    def_a <- conds[grepl("MIX.?A|MIXA|mix.?a|_A$|\\bA\\b", conds, perl = TRUE)][1]
    def_b <- conds[grepl("MIX.?B|MIXB|mix.?b|_B$|\\bB\\b", conds, perl = TRUE)][1]
    tagList(
      selectInput("mix_a", "Mix A:",
                  choices  = conds, multiple = TRUE,
                  selected = if (!is.na(def_a)) def_a else conds[1]),
      selectInput("mix_b", "Mix B:",
                  choices  = conds, multiple = TRUE,
                  selected = if (!is.na(def_b)) def_b else conds[min(2, length(conds))])
    )
  })

  # ── Main analysis ──────────────────────────────────────────────────────────
  results <- eventReactive(input$run_btn, {
    req(raw_data(), input$mix_a, input$mix_b)

    withProgress(message = "Processing…", value = 0, {

      setProgress(0.05, detail = "Validating columns")
      data <- raw_data()
      missing <- validate_columns(data)
      if (length(missing) > 0) {
        showNotification(
          paste("Missing columns:", paste(missing, collapse = ", ")),
          type = "error", duration = 20
        )
        return(NULL)
      }

      # Build organism map before any filtering
      org_map <- build_organism_map(data)

      setProgress(0.10, detail = "Filtering and recoding conditions")
      data <- data %>%
        select(all_of(REQUIRED_COLS)) %>%
        filter(F.FrgLossType == "noloss",
               R.Condition %in% c(input$mix_a, input$mix_b)) %>%
        mutate(R.Condition = case_when(
          R.Condition %in% input$mix_a ~ "MIX-A",
          R.Condition %in% input$mix_b ~ "MIX-B",
          TRUE ~ R.Condition
        ))

      if (input$data_level == "precursor") {
        setProgress(0.15, detail = "Collapsing to MS1 precursor level")
        data <- data %>%
          mutate(
            F.Charge                    = str_split_i(FG.Id, "_\\.", 2),
            F.FrgIon                    = str_remove_all(FG.Id, "_"),
            F.FrgMz                     = FG.PrecMz,
            F.FrgNum                    = FG.Id,
            F.FrgType                   = FG.Id,
            F.ExcludedFromQuantification = FALSE,
            F.PeakArea                  = FG.MS1RawQuantity
          ) %>%
          distinct()
      }

      setProgress(0.20, detail = "Converting to MSstats format (SpectronauttoMSstatsFormat)")
      data1 <- tryCatch(
        MSstatsConvert::SpectronauttoMSstatsFormat(data),
        error = function(e) {
          showNotification(paste("MSstatsConvert:", e$message), type = "error", duration = 15)
          NULL
        }
      )
      if (is.null(data1)) return(NULL)

      setProgress(0.30, detail = "Running dataProcess — this may take several minutes")
      n_cores <- max(1L, parallel::detectCores(logical = FALSE) - 1L)
      msstats_result <- tryCatch(
        MSstats::dataProcess(
          data1,
          normalization = FALSE,
          MBimpute      = FALSE,
          summaryMethod = "TMP",
          numberOfCores = n_cores
        ),
        error = function(e) {
          showNotification(paste("MSstats:", e$message), type = "error", duration = 15)
          NULL
        }
      )
      if (is.null(msstats_result)) return(NULL)
      rm(data1); gc()

      n_rep    <- input$n_replicates
      rep_cols <- as.character(seq_len(n_rep))

      # ── Protein-level (PG) ──────────────────────────────────────────────
      setProgress(0.65, detail = "Protein-level processing")
      PGdata <- msstats_result$ProteinLevelData
      PGdata$PG.ProteinGroups <- PGdata$Protein

      PGdata_org   <- add_organism_labels_pg(PGdata, org_map)
      avail_pg     <- intersect(rep_cols, unique(as.character(PGdata_org$SUBJECT)))

      PGdata_long <- PGdata_org %>%
        pivot_wider(
          id_cols     = c("Protein", "organism", "GROUP"),
          names_from  = "SUBJECT",
          values_from = "LogIntensities"
        ) %>%
        mutate(
          across(all_of(avail_pg), ~ 2^.x, .names = "ab_{.col}"),
          num_of_measurements = rowSums(!is.na(across(all_of(avail_pg)))),
          PG.CV = {
            ac <- paste0("ab_", avail_pg)
            (rowSDs(across(all_of(ac)), num_of_measurements) /
               rowMeans(across(all_of(ac)), na.rm = TRUE)) * 100
          },
          use_for_plots = num_of_measurements == n_rep,
          FRACTION = 1L
        ) %>%
        filter(use_for_plots) %>%
        select(Protein, organism, GROUP, FRACTION, num_of_measurements, PG.CV,
               all_of(avail_pg)) %>%
        pivot_longer(all_of(avail_pg), names_to = "replicate", values_to = "log2int")

      PGdata_long <- normalize_by_hela(PGdata_long)
      pg_summary  <- build_ratio_summary(
        PGdata_long,
        id_cols  = c("Protein", "organism", "GROUP"),
        rep_cols = avail_pg
      )

      # ── Feature-level (FG) ──────────────────────────────────────────────
      setProgress(0.78, detail = "Feature-level processing")
      FGdata <- msstats_result$FeatureLevelData %>%
        mutate(PRECURSOR = PEPTIDE, log2int = ABUNDANCE) %>%
        select(PROTEIN, PRECURSOR, GROUP, SUBJECT, FRACTION, log2int)

      FGdata_org <- add_organism_labels_fg(FGdata, org_map)
      avail_fg   <- intersect(rep_cols, unique(as.character(FGdata_org$SUBJECT)))

      FGdata_long <- FGdata_org %>%
        pivot_wider(
          id_cols     = c("PRECURSOR", "PROTEIN", "organism", "GROUP", "FRACTION"),
          names_from  = "SUBJECT",
          values_from = "log2int"
        ) %>%
        mutate(
          across(all_of(avail_fg), ~ 2^.x, .names = "ab_{.col}"),
          num_of_measurements = rowSums(!is.na(across(all_of(avail_fg)))),
          FG.CV = {
            ac <- paste0("ab_", avail_fg)
            (rowSDs(across(all_of(ac)), num_of_measurements) /
               rowMeans(across(all_of(ac)), na.rm = TRUE)) * 100
          },
          use_for_plots = num_of_measurements == n_rep
        ) %>%
        filter(use_for_plots) %>%
        select(PRECURSOR, PROTEIN, organism, GROUP, FRACTION,
               num_of_measurements, FG.CV, all_of(avail_fg)) %>%
        pivot_longer(all_of(avail_fg), names_to = "replicate", values_to = "log2int")

      FGdata_long <- normalize_by_hela(FGdata_long)
      fg_summary  <- build_ratio_summary(
        FGdata_long,
        id_cols  = c("PRECURSOR", "PROTEIN", "organism", "GROUP"),
        rep_cols = avail_fg
      )

      # ── S-curve ranks ────────────────────────────────────────────────────
      setProgress(0.90, detail = "Building S-curve data")
      sma_n <- input$sma_window

      FGdata_4 <- pivot_wider(
        FGdata_long,
        id_cols     = c("PRECURSOR", "PROTEIN", "organism", "GROUP"),
        names_from  = "replicate",
        values_from = "Normalized_log2int"
      ) %>%
        mutate(mean_log2 = rowMeans(across(all_of(avail_fg)), na.rm = TRUE))

      scurve_E <- scurve_to_long(build_scurve_ranks(FGdata_4, "E.COLI", sma_n))
      scurve_H <- scurve_to_long(build_scurve_ranks(FGdata_4, "HELA",   sma_n))
      scurve_Y <- scurve_to_long(build_scurve_ranks(FGdata_4, "YEAST",  sma_n))

      setProgress(1.0, detail = "Done!")

      list(
        pg_summary  = pg_summary,
        fg_summary  = fg_summary,
        PGdata_long = PGdata_long,
        FGdata_long = FGdata_long,
        scurve_E    = scurve_E,
        scurve_H    = scurve_H,
        scurve_Y    = scurve_Y,
        data_level  = input$data_level,
        ratio_H     = input$ratio_H,
        ratio_E     = input$ratio_E,
        ratio_Y     = input$ratio_Y
      )
    })
  })

  # ── Derived reactives ──────────────────────────────────────────────────────
  summary_df <- reactive({
    req(results())
    r <- results()
    if (r$data_level == "precursor") r$pg_summary else r$fg_summary
  })

  ylims <- reactive({
    req(summary_df())
    df <- summary_df() %>% filter(!is.na(log2AB))
    lo <- max(-8, floor(quantile(df$log2AB, 0.001, na.rm = TRUE)) - 0.5)
    hi <- min(8,  ceiling(quantile(df$log2AB, 0.999, na.rm = TRUE)) + 0.5)
    c(lo, hi)
  })

  ratio_plt <- reactive({
    req(summary_df(), results())
    r <- results()
    make_ratio_plot(summary_df(), r$ratio_H, r$ratio_E, r$ratio_Y, ylims())
  })

  scurve_E_plt <- reactive({
    req(results())
    r <- results()
    make_scurve_plot(r$scurve_E, "E.COLI", r$ratio_E, "#cc6600",
                     y_limits_top = c(7, 25), y_limits_sma = c(10, 25))
  })

  scurve_H_plt <- reactive({
    req(results())
    r <- results()
    make_scurve_plot(r$scurve_H, "HELA", r$ratio_H, "#00b050",
                     y_limits_top = c(6, 24), y_limits_sma = c(10, 22))
  })

  scurve_Y_plt <- reactive({
    req(results())
    r <- results()
    make_scurve_plot(r$scurve_Y, "YEAST", r$ratio_Y, "#6699ff",
                     y_limits_top = c(6, 24), y_limits_sma = c(10, 22))
  })

  # ── Main panel UI ──────────────────────────────────────────────────────────
  output$main_panel <- renderUI({
    if (is.null(results())) {
      return(div(
        class = "text-center mt-5 text-muted",
        tags$i(class = "bi bi-bar-chart-fill", style = "font-size:4rem;"),
        h4("Upload a file and click Generate Plots", class = "mt-3"),
        p("Accepts Spectronaut TSV/CSV reports with standard MSstats columns.")
      ))
    }

    navset_card_tab(
      id = "main_tabs",
      nav_panel("Ratio Plot",
        plotOutput("ratio_plot", height = "520px"),
        hr(),
        h5("Benchmark Statistics"),
        tableOutput("stats_tbl")
      ),
      nav_panel("S-Curves: E. Coli", plotOutput("sc_E", height = "720px")),
      nav_panel("S-Curves: HeLa",    plotOutput("sc_H", height = "720px")),
      nav_panel("S-Curves: Yeast",   plotOutput("sc_Y", height = "720px")),
      nav_panel("CV Distribution",   plotOutput("cv_plot", height = "450px")),
      nav_panel("Data Table",        DTOutput("data_tbl"))
    )
  })

  output$ratio_plot <- renderPlot({ ratio_plt() })
  output$sc_E       <- renderPlot({ scurve_E_plt() })
  output$sc_H       <- renderPlot({ scurve_H_plt() })
  output$sc_Y       <- renderPlot({ scurve_Y_plt() })

  output$cv_plot <- renderPlot({
    req(results())
    r   <- results()
    dat <- if (r$data_level == "precursor") r$PGdata_long else r$FGdata_long
    cv  <- if (r$data_level == "precursor") "PG.CV" else "FG.CV"
    make_cv_plot(dat, cv)
  })

  output$stats_tbl <- renderTable({
    req(results())
    r <- results()
    make_stats_table(summary_df(), r$ratio_H, r$ratio_E, r$ratio_Y)
  }, striped = TRUE, hover = TRUE, digits = 3)

  output$data_tbl <- renderDT({
    req(summary_df())
    df <- summary_df() %>%
      select(any_of(c("Protein", "PRECURSOR", "PROTEIN", "organism",
                      "MIX-A", "MIX-B", "log2AB", "Abundance.Diff"))) %>%
      mutate(across(where(is.numeric), ~ round(.x, 4)))
    datatable(df, filter = "top",
              options = list(pageLength = 20, scrollX = TRUE))
  })

  # ── Downloads ──────────────────────────────────────────────────────────────
  output$download_panel <- renderUI({
    req(results())
    tagList(
      hr(),
      strong("Download"),
      br(), br(),
      downloadButton("dl_ratio",  "Ratio Plot (PNG)",        class = "btn-outline-primary btn-sm w-100 mb-1"),
      downloadButton("dl_sc_E",   "S-Curves E. coli (PNG)",  class = "btn-outline-primary btn-sm w-100 mb-1"),
      downloadButton("dl_sc_H",   "S-Curves HeLa (PNG)",     class = "btn-outline-primary btn-sm w-100 mb-1"),
      downloadButton("dl_sc_Y",   "S-Curves Yeast (PNG)",    class = "btn-outline-primary btn-sm w-100 mb-1"),
      downloadButton("dl_data",   "Summary Data (TSV)",      class = "btn-outline-secondary btn-sm w-100")
    )
  })

  output$dl_ratio <- downloadHandler(
    filename = function() paste0("ratio_plot_", Sys.Date(), ".png"),
    content  = function(f) ggsave(f, ratio_plt(), width = 14, height = 6, dpi = 150, bg = "white")
  )
  output$dl_sc_E <- downloadHandler(
    filename = function() paste0("scurves_ecoli_", Sys.Date(), ".png"),
    content  = function(f) ggsave(f, scurve_E_plt(), width = 10, height = 12, dpi = 150, bg = "white")
  )
  output$dl_sc_H <- downloadHandler(
    filename = function() paste0("scurves_hela_", Sys.Date(), ".png"),
    content  = function(f) ggsave(f, scurve_H_plt(), width = 10, height = 12, dpi = 150, bg = "white")
  )
  output$dl_sc_Y <- downloadHandler(
    filename = function() paste0("scurves_yeast_", Sys.Date(), ".png"),
    content  = function(f) ggsave(f, scurve_Y_plt(), width = 10, height = 12, dpi = 150, bg = "white")
  )
  output$dl_data <- downloadHandler(
    filename = function() paste0("summary_", Sys.Date(), ".tsv"),
    content  = function(f) write_tsv(summary_df(), f)
  )
}

shinyApp(ui, server)
