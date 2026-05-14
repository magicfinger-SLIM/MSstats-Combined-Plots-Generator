# Allow uploads up to 5 GB
options(shiny.maxRequestSize = 5 * 1024^3)

# MSstats HYE Mix Ratio Plot Generator
# Input: Spectronaut report (.tsv or .csv)
# Generates: Scatter/Box/Density plots + S-curve plots for HeLa, Yeast, E.coli

APP_VERSION <- "1.0.0"
APP_DATE    <- "2026-05-13"

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(tidyverse)
  library(ggplot2)
  library(patchwork)
})

# ── UI ────────────────────────────────────────────────────────────────────────

ui <- page_sidebar(
  title = tags$span(
    "MSstats HYE Mix Ratio Plot Generator",
    tags$small(class = "ms-2 text-white-50 fw-normal",
               paste0("v", APP_VERSION))
  ),
  theme = bs_theme(bootswatch = "flatly", base_font = font_google("Inter")),

  sidebar = sidebar(
    width = 310,
    open = "open",

    # ── Input ──
    accordion(
      open = c("p1", "p2", "p3", "p4"),

      accordion_panel(
        "1  Upload Data", id = "p1",
        fileInput("file", NULL,
                  accept   = c(".tsv", ".csv"),
                  multiple = FALSE,
                  placeholder = "Spectronaut report (.tsv/.csv)"),
        radioButtons("mode", "Quantification level",
                     choices = c(
                       "MS1 Precursor (FG.MS1RawQuantity)" = "ms1",
                       "MS2 Fragment  (F.PeakArea)"        = "ms2"
                     ),
                     selected = "ms1"),
        tags$small(class = "text-muted",
          "Or load a saved MSstats summary (.rda) to skip re-processing:"),
        fileInput("rda_file", NULL, accept = ".rda",
                  placeholder = "Optional: saved summary .rda")
      ),

      accordion_panel(
        "2  Condition Names", id = "p2",
        textInput("mixa_name", "Mix A label (in R.Condition)", value = "MIX-A"),
        textInput("mixb_name", "Mix B label (in R.Condition)", value = "MIX-B"),
        numericInput("n_reps", "Replicates required per condition",
                     value = 4, min = 2, max = 20)
      ),

      accordion_panel(
        "3  Expected Log₂ Ratios (MixA/MixB)", id = "p3",
        numericInput("ratio_H", "HeLa (Homo sapiens)",      value =  0, step = 0.5),
        numericInput("ratio_Y", "Yeast (Saccharomyces)",    value =  1, step = 0.5),
        numericInput("ratio_E", "E.coli (Escherichia)",     value = -2, step = 0.5),
        tags$small(class = "text-muted",
          "Leave iRT / spike-in proteins excluded automatically.")
      ),

      accordion_panel(
        "4  Download Options", id = "p4",
        selectInput("dl_format", "Format",
                    choices  = c("PNG" = "png", "PDF" = "pdf", "SVG" = "svg"),
                    selected = "png"),
        fluidRow(
          column(6, numericInput("dl_w", "Width (px)",  value = 1500, min = 500, step = 100)),
          column(6, numericInput("dl_h", "Height (px)", value =  650, min = 300, step = 100))
        ),
        numericInput("dl_dpi", "DPI", value = 150, min = 72, max = 600, step = 25),
        downloadButton("dl_scatter", "Scatter + Box + Density",
                       class = "btn-outline-success w-100 mb-1"),
        downloadButton("dl_ecoli",   "S-Curves: E.coli",
                       class = "btn-outline-warning  w-100 mb-1"),
        downloadButton("dl_hela",    "S-Curves: HeLa",
                       class = "btn-outline-success  w-100 mb-1"),
        downloadButton("dl_yeast",   "S-Curves: Yeast",
                       class = "btn-outline-primary  w-100 mb-1"),
        downloadButton("dl_all",     "All Plots (combined)",
                       class = "btn-success           w-100")
      )
    ),

    hr(),
    actionButton("run", "Generate Plots",
                 class = "btn-primary btn-lg w-100",
                 icon  = icon("chart-bar"))
  ),

  # ── Main panel ──
  navset_tab(
    nav_panel(
      "Scatter / Box / Density",
      br(),
      uiOutput("stats_cards"),
      br(),
      plotOutput("plot_combo", height = "500px")
    ),
    nav_panel(
      "S-Curves: E.coli",
      br(),
      plotOutput("plot_ecoli", height = "760px")
    ),
    nav_panel(
      "S-Curves: HeLa",
      br(),
      plotOutput("plot_hela", height = "760px")
    ),
    nav_panel(
      "S-Curves: Yeast",
      br(),
      plotOutput("plot_yeast", height = "760px")
    ),
    nav_panel(
      "Log",
      br(),
      verbatimTextOutput("log_out")
    ),

    nav_panel(
      icon("circle-info", lib = "font-awesome"),
      value = "about",
      br(),
      fluidRow(
        column(8, offset = 2,

          # ── Header ──
          div(class = "card mb-4",
            div(class = "card-body",
              fluidRow(
                column(9,
                  h3("MSstats HYE Mix Ratio Plot Generator"),
                  p(class = "text-muted mb-1",
                    strong("Version: "), APP_VERSION, " · ",
                    strong("Released: "), APP_DATE),
                  p("A Shiny tool for quantitative benchmarking of data-independent ",
                    "acquisition (DIA) proteomics experiments using a three-species ",
                    "(HeLa / Yeast / E. coli) mixed proteome standard. Accepts raw ",
                    "Spectronaut reports and produces publication-ready ratio plots ",
                    "via the MSstats pipeline.")
                ),
                column(3, class = "text-center pt-3",
                  tags$img(src = "https://www.bioconductor.org/shields/years-in-bioc/MSstats.svg",
                           style = "max-width:100%;"),
                  br(), br(),
                  tags$span(class = "badge bg-primary", "DIA Proteomics"),
                  tags$span(class = "badge bg-success ms-1", "HYE Benchmark")
                )
              )
            )
          ),

          # ── Input requirements ──
          div(class = "card mb-4",
            div(class = "card-header fw-bold", icon("file-csv"), " Required Input Columns"),
            div(class = "card-body",
              p("Upload a Spectronaut export (.tsv or .csv) containing all 29 columns below.",
                "Export using the MSstats-compatible Spectronaut report schema."),
              tags$table(class = "table table-sm table-striped table-bordered",
                tags$thead(tags$tr(
                  tags$th("Column group"), tags$th("Columns")
                )),
                tags$tbody(
                  tags$tr(tags$td("Run / condition"),
                    tags$td(tags$code("R.Condition, R.FileName, R.Replicate"))),
                  tags$tr(tags$td("Protein group"),
                    tags$td(tags$code("PG.Organisms, PG.ProteinAccessions, PG.ProteinGroups, PG.Qvalue, PG.Quantity"))),
                  tags$tr(tags$td("Peptide"),
                    tags$td(tags$code("PEP.GroupingKey, PEP.StrippedSequence, PEP.Quantity"))),
                  tags$tr(tags$td("EG / precursor"),
                    tags$td(tags$code("EG.iRTPredicted, EG.Library, EG.ModifiedSequence, EG.PrecursorId, EG.Qvalue"))),
                  tags$tr(tags$td("Fragment group (FG)"),
                    tags$td(tags$code("FG.Charge, FG.Id, FG.PrecMz, FG.Quantity, FG.MS1RawQuantity"))),
                  tags$tr(tags$td("Fragment (F)"),
                    tags$td(tags$code("F.Charge, F.FrgIon, F.FrgLossType, F.FrgMz, F.FrgNum, F.FrgType, F.ExcludedFromQuantification, F.PeakArea")))
                )
              )
            )
          ),

          # ── Pipeline ──
          div(class = "card mb-4",
            div(class = "card-header fw-bold", icon("diagram-project"), " Analysis Pipeline"),
            div(class = "card-body",
              tags$ol(class = "ps-3",
                tags$li(class = "mb-3",
                  strong("Data ingestion & mode selection"),
                  tags$ul(
                    tags$li(tags$code("F.FrgLossType == \"noloss\""), " filter applied to all data."),
                    tags$li(strong("MS1 mode:"), " fragment columns are overwritten with precursor-level values
                      (", tags$code("F.PeakArea ← FG.MS1RawQuantity"), ", ", tags$code("F.FrgMz ← FG.PrecMz"),
                      ") — each precursor is treated as a single 'feature'."),
                    tags$li(strong("MS2 mode:"), " raw fragment peak areas (", tags$code("F.PeakArea"), ")
                      are used; multiple fragments per precursor are mean-collapsed during pivoting.")
                  )
                ),
                tags$li(class = "mb-3",
                  strong("MSstats processing"),
                  tags$ul(
                    tags$li(tags$code("SpectronauttoMSstatsFormat()"), " converts the Spectronaut table to MSstats input."),
                    tags$li(tags$code("dataProcess(normalization = FALSE, MBimpute = FALSE, summaryMethod = \"TMP\")"),
                      " summarises features to protein level without normalization or imputation."),
                    tags$li("Output: ", tags$code("ProteinLevelData"), " (log₂ intensities) and ",
                      tags$code("FeatureLevelData"), " (precursor/fragment abundances).")
                  )
                ),
                tags$li(class = "mb-3",
                  strong("Species assignment"),
                  tags$ul(
                    tags$li("Proteins labelled via ", tags$code("PG.Organisms"), ":"),
                    tags$li(tags$span(style = "color:#00b050", "● HELA"), " — contains 'Homo sapiens', excludes Saccharomyces & Escherichia"),
                    tags$li(tags$span(style = "color:#6699ff", "● YEAST"), " — contains 'Saccharomyces', excludes Homo sapiens & Escherichia"),
                    tags$li(tags$span(style = "color:#cc6600", "● E.COLI"), " — contains 'Escherichia', excludes Homo sapiens & Saccharomyces"),
                    tags$li("Proteins matching multiple species (contaminants, iRT) are excluded.")
                  )
                ),
                tags$li(class = "mb-3",
                  strong("HeLa-median run normalisation"),
                  tags$ul(
                    tags$li("Median log₂ intensity of HeLa proteins is computed per (condition × replicate) run."),
                    tags$li("A single experiment-wide median is computed across all HeLa runs."),
                    tags$li("Normalised intensity = raw log₂ − run median + experiment median."),
                    tags$li("Applied identically to HeLa, Yeast, and E.coli.")
                  )
                ),
                tags$li(class = "mb-3",
                  strong("Ratio calculation"),
                  tags$ul(
                    tags$li("Normalised log₂ intensities are averaged across replicates within each condition."),
                    tags$li("log₂ ratio = mean(MixA) − mean(MixB) per protein / precursor."),
                    tags$li("Only IDs with data in ", em("all"), " required replicates (default: 4/4) are retained.")
                  )
                ),
                tags$li(class = "mb-3",
                  strong("S-curve rank ordering"),
                  tags$ul(
                    tags$li("Precursors ranked in descending order of their MixB mean log₂ intensity."),
                    tags$li("Simple Moving Average (SMA, window = 150) applied to MixA and MixB traces."),
                    tags$li("Difference curve (SMA.A − SMA.B) compared to expected log₂ ratio.")
                  )
                )
              )
            )
          ),

          # ── Outputs ──
          div(class = "card mb-4",
            div(class = "card-header fw-bold", icon("chart-line"), " Output Plots"),
            div(class = "card-body",
              tags$table(class = "table table-sm table-bordered",
                tags$thead(tags$tr(
                  tags$th("Tab"), tags$th("Plot"), tags$th("Description")
                )),
                tags$tbody(
                  tags$tr(
                    tags$td(tags$strong("Scatter / Box / Density")),
                    tags$td("Combined (patchwork)"),
                    tags$td("Left: scatter of log₂ ratio vs MixB abundance, coloured by species.
                      Centre: density distribution of log₂ ratios.
                      Right: box plot per species. Dashed lines = expected ratios.")
                  ),
                  tags$tr(
                    tags$td(tags$strong("S-Curves: E.coli")),
                    tags$td("3-panel rank plot"),
                    tags$td("Top: raw precursor intensities for MixA & MixB ranked by MixB.
                      Middle: SMA smoothed traces. Bottom: measured vs expected log₂ ratio.")
                  ),
                  tags$tr(
                    tags$td(tags$strong("S-Curves: HeLa")),
                    tags$td("3-panel rank plot"),
                    tags$td("Same as E.coli panel; expected ratio = 0 (1:1 mix).")
                  ),
                  tags$tr(
                    tags$td(tags$strong("S-Curves: Yeast")),
                    tags$td("3-panel rank plot"),
                    tags$td("Same as E.coli panel; expected ratio = 1 (2:1 mix).")
                  ),
                  tags$tr(
                    tags$td(tags$strong("Log")),
                    tags$td("Text"),
                    tags$td("Timestamped processing log for each run.")
                  )
                )
              )
            )
          ),

          # ── Download ──
          div(class = "card mb-4",
            div(class = "card-header fw-bold", icon("download"), " Download Options"),
            div(class = "card-body",
              tags$ul(
                tags$li(strong("Format:"), " PNG (raster), PDF (vector), SVG (vector)."),
                tags$li(strong("Resolution:"), " configurable DPI (default 150)."),
                tags$li(strong("Size:"), " width × height in pixels (default 1500 × 650 for the combined plot)."),
                tags$li(strong("Individual downloads:"), " Scatter/Box/Density, and each S-curve species separately."),
                tags$li(strong("Combined download:"), " all plots stacked into a single file.")
              )
            )
          ),

          # ── Tips ──
          div(class = "card mb-4",
            div(class = "card-header fw-bold", icon("lightbulb"), " Tips & Notes"),
            div(class = "card-body",
              tags$ul(
                tags$li("For large files (> 1 GB), run ", tags$code("dataProcess"), " once in R,
                  save the result with ", tags$code("save(msstats_summarized, file = \"summary.rda\")"),
                  ", then upload the .rda file to skip re-processing."),
                tags$li(tags$code("R.Condition"), " values must exactly match the Mix-A / Mix-B labels
                  entered in the sidebar (case-sensitive)."),
                tags$li("Species keywords (Homo sapiens, Saccharomyces, Escherichia) are matched as
                  substrings of ", tags$code("PG.Organisms"), " — ensure Spectronaut uses full taxonomy names."),
                tags$li("SMA window (150 precursors) is optimised for experiments with thousands of
                  precursors per species; smaller experiments may show flat SMA traces near the ends."),
                tags$li("The tool runs MSstats on all available CPU cores minus 2 to keep the system responsive.")
              )
            )
          ),

          # ── Footer ──
          div(class = "text-center text-muted small pb-4",
            paste0("MSstats HYE Mix Ratio Plot Generator  v", APP_VERSION,
                   "  ·  ", APP_DATE),
            br(),
            "Powered by ",
            tags$a("MSstats", href = "https://msstats.org", target = "_blank"), " · ",
            tags$a("MSstatsConvert", href = "https://bioconductor.org/packages/MSstatsConvert", target = "_blank"), " · ",
            tags$a("Shiny", href = "https://shiny.posit.co", target = "_blank"), " · ",
            tags$a("ggplot2", href = "https://ggplot2.tidyverse.org", target = "_blank"), " · ",
            tags$a("patchwork", href = "https://patchwork.data-imaginist.com", target = "_blank")
          )
        )
      )
    )
  )
)

# ── Server ────────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  # ── Reactive log ──
  rv_log  <- reactiveVal(character(0))
  rv_plots <- reactiveValues(combo = NULL, ecoli = NULL,
                              hela = NULL, yeast = NULL, stats = NULL)

  log_msg <- function(...) {
    msg <- paste0("[", format(Sys.time(), "%H:%M:%S"), "] ", ...)
    rv_log(c(rv_log(), msg))
    message(msg)
  }

  output$log_out <- renderText(paste(rv_log(), collapse = "\n"))

  # ── Helper: row SD ──
  row_sds <- function(mat, n) {
    sqrt(rowSums((mat - rowMeans(mat, na.rm = TRUE))^2, na.rm = TRUE) / (n - 1))
  }

  # ── Helper: assign organism labels ──
  make_uniprot_sets <- function(raw) {
    list(
      H = raw %>%
        filter( str_detect(PG.Organisms, "Homo sapiens") &
               !str_detect(PG.Organisms, "Saccharomyces|Escherichia")) %>%
        select(PG.ProteinGroups) %>% distinct(),
      Y = raw %>%
        filter( str_detect(PG.Organisms, "Saccharomyces") &
               !str_detect(PG.Organisms, "Homo sapiens|Escherichia")) %>%
        select(PG.ProteinGroups) %>% distinct(),
      E = raw %>%
        filter( str_detect(PG.Organisms, "Escherichia") &
               !str_detect(PG.Organisms, "Homo sapiens|Saccharomyces")) %>%
        select(PG.ProteinGroups) %>% distinct()
    )
  }

  # ── Helper: HeLa-based normalisation ──
  normalize_by_hela <- function(df_long, group_col = "GROUP",
                                 rep_col = "replicate", frac_col = "FRACTION",
                                 val_col = "log2int") {
    data_H <- df_long %>% filter(organism == "HELA")

    run_med <- data_H %>%
      group_by(across(all_of(c(group_col, rep_col)))) %>%
      summarise(med_run  = median(.data[[val_col]], na.rm = TRUE), .groups = "drop")

    frac_med <- data_H %>%
      group_by(across(all_of(frac_col))) %>%
      summarise(med_frac = median(.data[[val_col]], na.rm = TRUE), .groups = "drop")

    df_long %>%
      left_join(run_med,  by = c(group_col, rep_col)) %>%
      left_join(frac_med, by = frac_col) %>%
      mutate(Normalized_log2int = .data[[val_col]] - med_run + med_frac) %>%
      select(-med_run, -med_frac)
  }

  # ── Helper: scatter + box + density combined plot ──
  make_combo_plot <- function(df, mixb_col, ratio_H, ratio_Y, ratio_E) {
    pal <- c("E.COLI" = "#cc6600", "HELA" = "#00b050", "YEAST" = "#6699ff")

    y_q <- quantile(df$log2AB, c(0.005, 0.995), na.rm = TRUE)
    y_min <- floor(y_q[1] * 2) / 2
    y_max <- ceiling(y_q[2] * 2) / 2

    base_theme <- theme_minimal() +
      theme(
        panel.grid.major  = element_blank(),
        panel.grid.minor  = element_blank(),
        axis.line         = element_line(color = "black"),
        axis.text         = element_text(size = 14, color = "black"),
        axis.title        = element_text(size = 16),
        axis.ticks        = element_line(color = "black")
      )

    hlines <- list(
      geom_hline(yintercept = ratio_H, linetype = 2, color = "#00b050"),
      geom_hline(yintercept = ratio_E, linetype = 2, color = "#cc6600"),
      geom_hline(yintercept = ratio_Y, linetype = 2, color = "#6699ff")
    )

    p1 <- ggplot(df, aes(x = .data[[mixb_col]], y = log2AB, color = organism)) +
      base_theme +
      theme(legend.position = "none",
            plot.margin = unit(c(1, 0, 1, 1), "cm")) +
      geom_point(size = 0.7, alpha = 0.3) +
      scale_color_manual(values = pal) +
      scale_y_continuous(limits = c(y_min, y_max), expand = c(0, 0)) +
      xlab(expression("Log"[2] ~ "[MixB Protein Abundance]")) +
      ylab(expression("Log"[2] ~ "ratio [MixA/MixB]")) +
      hlines

    p2 <- ggplot(df, aes(x = organism, y = log2AB, fill = organism)) +
      base_theme +
      theme(axis.text.y   = element_blank(),
            axis.title.y  = element_blank(),
            axis.line.y   = element_blank(),
            axis.text.x   = element_text(size = 14),
            axis.title.x  = element_text(size = 16),
            legend.title  = element_text(size = 16),
            legend.text   = element_text(size = 14),
            plot.margin   = unit(c(1, 1, 1, 0), "cm")) +
      stat_boxplot(geom = "errorbar", width = 0.15) +
      geom_boxplot() +
      scale_fill_manual(values = pal) +
      scale_y_continuous(limits = c(y_min, y_max), expand = c(0, 0)) +
      scale_x_discrete(labels = c("E.COLI" = "E", "HELA" = "H", "YEAST" = "Y")) +
      ylab(expression("Log"[2] ~ "ratio [MixA/MixB]")) +
      xlab("Organism") +
      hlines

    p3 <- ggplot(df, aes(y = log2AB, fill = organism, colour = organism)) +
      base_theme +
      theme(axis.text.y  = element_blank(),
            axis.title.y = element_blank(),
            axis.line.y  = element_blank(),
            axis.text.x  = element_text(size = 14),
            axis.title.x = element_text(size = 16, color = "black"),
            legend.position = "none",
            plot.margin  = unit(c(1, 0.5, 1, 0.5), "cm")) +
      geom_density(linewidth = 0.75, alpha = 0.4) +
      scale_y_continuous(limits = c(y_min, y_max), expand = c(0, 0)) +
      scale_x_continuous(breaks = c(0, 1, 2), expand = c(0, 0)) +
      xlab("Density") +
      scale_fill_manual(values   = c("E.COLI" = NA, "HELA" = NA, "YEAST" = NA)) +
      scale_color_manual(values  = pal) +
      hlines

    p1 + p3 + p2 + plot_layout(widths = c(10, 2, 2))
  }

  # ── Helper: S-curve triple panel ──
  make_scurve_plot <- function(fg4, org, org_label, color,
                                expected_ratio, mixa, mixb, sma_n = 150) {
    mixa_d <- fg4 %>% filter(organism == org, GROUP == mixa) %>%
      select(PRECURSOR, PROTEIN, organism, mean_log2)
    mixb_d <- fg4 %>% filter(organism == org, GROUP == mixb) %>%
      select(PRECURSOR, PROTEIN, organism, mean_log2)

    joined <- full_join(mixa_d, mixb_d,
                        by = c("PRECURSOR", "PROTEIN", "organism"),
                        suffix = c(".A", ".B")) %>%
      filter(!is.na(mean_log2.A) & !is.na(mean_log2.B)) %>%
      arrange(desc(mean_log2.B)) %>%
      mutate(
        SMA.A    = TTR::SMA(mean_log2.A, n = sma_n),
        SMA.B    = TTR::SMA(mean_log2.B, n = sma_n),
        SMA.diff = SMA.A - SMA.B,
        Rank     = row_number()
      )

    if (nrow(joined) == 0) return(NULL)

    data_long <- bind_rows(
      joined %>% mutate(mean = mean_log2.A, GROUP = mixa),
      joined %>% mutate(mean = mean_log2.B, GROUP = mixb)
    ) %>% mutate(GROUP = factor(GROUP, levels = c(mixa, mixb)))

    sc_theme <- theme_minimal() +
      theme(
        panel.grid.major = element_blank(), panel.grid.minor = element_blank(),
        axis.line   = element_line(color = "black"),
        axis.text   = element_text(size = 15, color = "black"),
        axis.title  = element_text(size = 15),
        axis.ticks  = element_line(color = "darkgray"),
        legend.title = element_text(size = 16), legend.text = element_text(size = 15)
      )

    pa <- ggplot(data_long, aes(x = Rank, y = mean, color = GROUP)) +
      sc_theme +
      theme(plot.title = element_text(size = 20),
            plot.margin = unit(c(1, 0, 1, 0), "cm")) +
      geom_point(size = 0.5) +
      scale_x_continuous(expand = c(0, 0)) +
      scale_color_manual(values = setNames(c("#e16462", "#7e03a8"), c(mixa, mixb))) +
      guides(color = guide_legend(override.aes = list(size = 3))) +
      xlab("Rank Order of Precursors in Mix B") +
      ylab(expression("Mean Log"[2] ~ "Intensity")) +
      ggtitle(org_label)

    pb <- ggplot(joined, aes(x = Rank)) +
      sc_theme +
      theme(plot.margin = unit(c(1, 0, 1, 0), "cm")) +
      geom_line(aes(y = SMA.A, color = mixa), linewidth = 1) +
      geom_line(aes(y = SMA.B, color = mixb), linewidth = 1) +
      scale_x_continuous(expand = c(0, 0)) +
      scale_color_manual(name = NULL,
                         values = setNames(c("#e16462", "#7e03a8"), c(mixa, mixb))) +
      xlab("Rank Order of Precursors in Mix B") +
      ylab("Simple Moving Avg.")

    pc <- ggplot(joined, aes(x = Rank)) +
      sc_theme +
      theme(plot.margin = unit(c(1, 0, 0, 0), "cm")) +
      geom_hline(aes(yintercept = expected_ratio, linetype = "Expected"),
                 color = "black", linewidth = 1) +
      geom_line(aes(y = SMA.diff, color = "Measured"), linewidth = 1) +
      scale_x_continuous(expand = c(0, 0)) +
      scale_color_manual(name   = NULL, values = c("Measured" = color)) +
      scale_linetype_manual(name = NULL, values = c("Expected" = "solid")) +
      guides(color    = guide_legend(override.aes = list(size = 3)),
             linetype = guide_legend(order = 2)) +
      xlab("Rank Order of Precursors in Mix B") +
      ylab(expression("Log"[2] ~ "Ratio [MixA/MixB]"))

    pa / pb / pc + plot_layout(guides = "keep")
  }

  # ── Main processing ──
  observeEvent(input$run, {

    # Reset
    rv_log(character(0))
    rv_plots$combo <- rv_plots$ecoli <- rv_plots$hela <-
      rv_plots$yeast <- rv_plots$stats <- NULL

    mixa   <- trimws(input$mixa_name)
    mixb   <- trimws(input$mixb_name)
    n_reps <- input$n_reps
    rep_cols <- as.character(seq_len(n_reps))

    ratio_H <- input$ratio_H
    ratio_Y <- input$ratio_Y
    ratio_E <- input$ratio_E

    withProgress(message = "Running MSstats pipeline…", value = 0, {

      tryCatch({

        # ── Step 1: Load or process MSstats summary ──
        mss <- NULL

        if (!is.null(input$rda_file)) {
          incProgress(0.05, detail = "Loading saved MSstats summary…")
          log_msg("Loading pre-saved MSstats summary from .rda file…")
          env <- new.env()
          load(input$rda_file$datapath, envir = env)
          obj_names <- ls(env)
          # Take first object that looks like an MSstats summary
          mss <- env[[obj_names[1]]]
          log_msg(paste("Loaded object:", obj_names[1]))
        }

        # Raw data needed for organism assignment (required regardless)
        req(input$file)

        incProgress(0.08, detail = "Reading Spectronaut report…")
        log_msg("Reading Spectronaut report…")

        ext <- tools::file_ext(input$file$name)
        raw <- if (ext == "tsv") {
          read_tsv(input$file$datapath, show_col_types = FALSE)
        } else {
          read_csv(input$file$datapath, show_col_types = FALSE)
        }
        log_msg(paste0("Loaded ", nrow(raw), " rows × ", ncol(raw), " columns."))

        # Required columns
        needed <- c(
          "R.Condition", "R.FileName", "R.Replicate",
          "PG.Organisms", "PG.ProteinAccessions", "PG.ProteinGroups",
          "PG.Qvalue", "PG.Quantity",
          "PEP.GroupingKey", "PEP.StrippedSequence", "PEP.Quantity",
          "EG.iRTPredicted", "EG.Library", "EG.ModifiedSequence",
          "EG.PrecursorId", "EG.Qvalue",
          "FG.Charge", "FG.Id", "FG.PrecMz", "FG.Quantity", "FG.MS1RawQuantity",
          "F.Charge", "F.FrgIon", "F.FrgLossType", "F.FrgMz",
          "F.FrgNum", "F.FrgType", "F.ExcludedFromQuantification", "F.PeakArea"
        )
        missing_c <- setdiff(needed, colnames(raw))
        if (length(missing_c) > 0) {
          stop(paste("Missing required columns:", paste(missing_c, collapse = ", ")))
        }

        # ── Step 2: Prepare MSstats-formatted data ──
        incProgress(0.12, detail = "Reformatting for MSstats…")
        log_msg(paste("Mode:", input$mode))

        data_filt <- raw %>%
          select(all_of(needed)) %>%
          filter(F.FrgLossType == "noloss")

        if (input$mode == "ms1") {
          data_filt <- data_filt %>%
            mutate(
              F.Charge                    = str_split_i(FG.Id, "_\\.", 2),
              F.FrgIon                    = str_remove_all(FG.Id, "_"),
              F.FrgMz                     = FG.PrecMz,
              F.FrgNum                    = FG.Id,
              F.FrgType                   = FG.Id,
              F.ExcludedFromQuantification = FALSE,
              F.PeakArea                  = FG.MS1RawQuantity
            )
        }
        data_filt <- distinct(data_filt)
        log_msg(paste0("Filtered data: ", nrow(data_filt), " rows."))

        # ── Step 3: MSstats dataProcess (skip if .rda loaded) ──
        if (is.null(mss)) {
          suppressPackageStartupMessages({
            library(MSstatsConvert)
            library(MSstats)
          })

          incProgress(0.15, detail = "Converting to MSstats format…")
          log_msg("SpectronauttoMSstatsFormat…")
          data_ms <- SpectronauttoMSstatsFormat(data_filt)

          incProgress(0.20, detail = "Running dataProcess (may take several minutes)…")
          log_msg("dataProcess: normalization=FALSE, MBimpute=FALSE, TMP…")
          mss <- dataProcess(
            data_ms,
            normalization  = FALSE,
            MBimpute       = FALSE,
            summaryMethod  = "TMP",
            numberOfCores  = max(1L, parallel::detectCores() - 2L)
          )
          rm(data_ms)
          log_msg("dataProcess complete.")
        }

        # ── Step 4: Protein-level data ──
        incProgress(0.55, detail = "Processing protein-level data…")
        log_msg("Building protein-level data frame…")

        uniprot <- make_uniprot_sets(data_filt)
        PGdata  <- mss$ProteinLevelData
        PGdata$PG.ProteinGroups <- PGdata$Protein

        PGdata.H <- semi_join(PGdata, uniprot$H, by = "PG.ProteinGroups") %>% mutate(organism = "HELA")
        PGdata.Y <- semi_join(PGdata, uniprot$Y, by = "PG.ProteinGroups") %>% mutate(organism = "YEAST")
        PGdata.E <- semi_join(PGdata, uniprot$E, by = "PG.ProteinGroups") %>% mutate(organism = "E.COLI")
        PGdata_sp <- bind_rows(PGdata.E, PGdata.H, PGdata.Y)
        rm(PGdata, PGdata.H, PGdata.Y, PGdata.E)

        # Pivot to wide → compute measurements
        PGdata_wide <- pivot_wider(
          PGdata_sp,
          id_cols    = c("Protein", "organism", "GROUP"),
          names_from = "SUBJECT", values_from = "LogIntensities",
          values_fn  = \(x) mean(x, na.rm = TRUE)
        )
        missing_reps <- setdiff(rep_cols, colnames(PGdata_wide))
        if (length(missing_reps) > 0) {
          stop(paste("SUBJECT columns not found:", paste(missing_reps, collapse = ",")))
        }

        PGdata_wide <- PGdata_wide %>%
          mutate(
            across(all_of(rep_cols), ~ 2^.x, .names = "abund_{.col}"),
            n_meas = rowSums(!is.na(across(all_of(rep_cols))))
          )

        PGdata_long <- PGdata_wide %>%
          filter(n_meas == n_reps) %>%
          select(Protein, organism, GROUP, n_meas, all_of(rep_cols)) %>%
          pivot_longer(all_of(rep_cols), names_to = "replicate", values_to = "log2int") %>%
          mutate(FRACTION = 1L)

        PGdata_long  <- normalize_by_hela(PGdata_long)
        log_msg(paste("Protein-level: ", n_distinct(PGdata_long$Protein), " proteins after filtering."))

        PGdata_mean <- pivot_wider(
          PGdata_long,
          id_cols    = c("Protein", "organism", "GROUP"),
          names_from = "replicate", values_from = "Normalized_log2int"
        ) %>%
          mutate(mean_log2 = rowMeans(across(all_of(rep_cols)), na.rm = TRUE))

        pg_summary <- pivot_wider(
          PGdata_mean,
          id_cols    = c("Protein", "organism"),
          names_from = "GROUP", values_from = "mean_log2"
        ) %>%
          mutate(log2AB = .data[[mixa]] - .data[[mixb]])

        df_pg <- pg_summary %>%
          mutate(
            Abundance.MixA = 2^.data[[mixa]],
            Abundance.MixB = 2^.data[[mixb]],
            Abundance.Diff = Abundance.MixA / Abundance.MixB
          ) %>%
          filter(!is.na(Abundance.Diff))

        # ── Statistics ──
        calc_stats <- function(sub_df, expected_fc) {
          med_fc  <- median(sub_df$Abundance.Diff, na.rm = TRUE)
          pct_err <- round(abs(med_fc - expected_fc) / expected_fc * 100, 2)
          list(
            n          = nrow(sub_df),
            median_fc  = round(med_fc, 4),
            pct_error  = pct_err,
            sd_log2    = round(sd(sub_df$log2AB, na.rm = TRUE), 3)
          )
        }
        rv_plots$stats <- list(
          H = calc_stats(filter(df_pg, organism == "HELA"),   2^ratio_H),
          Y = calc_stats(filter(df_pg, organism == "YEAST"),  2^ratio_Y),
          E = calc_stats(filter(df_pg, organism == "E.COLI"), 2^ratio_E)
        )

        incProgress(0.65, detail = "Generating scatter/box/density plot…")
        log_msg("Building scatter/box/density plot…")
        rv_plots$combo <- make_combo_plot(df_pg, mixb, ratio_H, ratio_Y, ratio_E)

        # ── Step 5: Feature-level data for S-curves ──
        incProgress(0.70, detail = "Processing feature-level data for S-curves…")
        log_msg("Building feature-level data frame…")

        FGdata <- mss$FeatureLevelData %>%
          mutate(
            PRECURSOR = PEPTIDE,
            log2int   = ABUNDANCE
          ) %>%
          select(PROTEIN, PRECURSOR, GROUP, SUBJECT, RUN, FRACTION, log2int)

        uniprot_fg <- list(
          H = data_filt %>%
            filter( str_detect(PG.Organisms, "Homo sapiens") &
                   !str_detect(PG.Organisms, "Saccharomyces|Escherichia")) %>%
            select(PROTEIN = PG.ProteinGroups) %>% distinct(),
          Y = data_filt %>%
            filter( str_detect(PG.Organisms, "Saccharomyces") &
                   !str_detect(PG.Organisms, "Homo sapiens|Escherichia")) %>%
            select(PROTEIN = PG.ProteinGroups) %>% distinct(),
          E = data_filt %>%
            filter( str_detect(PG.Organisms, "Escherichia") &
                   !str_detect(PG.Organisms, "Homo sapiens|Saccharomyces")) %>%
            select(PROTEIN = PG.ProteinGroups) %>% distinct()
        )

        FGdata.H <- semi_join(FGdata, uniprot_fg$H, by = "PROTEIN") %>% mutate(organism = "HELA")
        FGdata.Y <- semi_join(FGdata, uniprot_fg$Y, by = "PROTEIN") %>% mutate(organism = "YEAST")
        FGdata.E <- semi_join(FGdata, uniprot_fg$E, by = "PROTEIN") %>% mutate(organism = "E.COLI")
        FGdata_2 <- bind_rows(FGdata.E, FGdata.H, FGdata.Y)
        rm(FGdata, FGdata.E, FGdata.H, FGdata.Y)

        FGdata_wide <- pivot_wider(
          FGdata_2,
          id_cols    = c("PRECURSOR", "PROTEIN", "organism", "GROUP", "FRACTION"),
          names_from = "SUBJECT", values_from = "log2int",
          values_fn  = \(x) mean(x, na.rm = TRUE)   # collapse duplicate fragments per precursor
        ) %>%
          mutate(n_meas = rowSums(!is.na(across(any_of(rep_cols))))) %>%
          filter(n_meas == n_reps)

        avail_rep_cols <- intersect(rep_cols, colnames(FGdata_wide))

        FGdata_long <- FGdata_wide %>%
          select(PRECURSOR, PROTEIN, organism, GROUP, FRACTION, n_meas,
                 all_of(avail_rep_cols)) %>%
          pivot_longer(all_of(avail_rep_cols),
                       names_to = "replicate", values_to = "log2int")

        FGdata_long <- normalize_by_hela(FGdata_long)
        log_msg(paste("Feature-level: ", n_distinct(FGdata_long$PRECURSOR),
                      " precursors after filtering."))

        FGdata_4 <- pivot_wider(
          FGdata_long,
          id_cols    = c("PRECURSOR", "PROTEIN", "organism", "GROUP"),
          names_from = "replicate", values_from = "Normalized_log2int"
        ) %>%
          mutate(mean_log2 = rowMeans(across(all_of(avail_rep_cols)), na.rm = TRUE))

        # ── Step 6: S-curve plots ──
        incProgress(0.85, detail = "Building S-curve plots…")
        log_msg("Building S-curve plots…")

        rv_plots$ecoli <- make_scurve_plot(FGdata_4, "E.COLI", "E. coli",
                                            "#cc6600", ratio_E, mixa, mixb)
        rv_plots$hela  <- make_scurve_plot(FGdata_4, "HELA",   "HeLa",
                                            "#00b050", ratio_H, mixa, mixb)
        rv_plots$yeast <- make_scurve_plot(FGdata_4, "YEAST",  "Yeast",
                                            "#6699ff", ratio_Y, mixa, mixb)

        incProgress(1.0, detail = "Done!")
        log_msg("All plots generated successfully.")
        showNotification("Plots ready!", type = "message", duration = 4)

      }, error = function(e) {
        log_msg(paste("ERROR:", conditionMessage(e)))
        showNotification(paste("Error:", conditionMessage(e)),
                         type = "error", duration = NULL)
      })
    })
  })

  # ── Statistics cards ──
  output$stats_cards <- renderUI({
    req(rv_plots$stats)
    s <- rv_plots$stats

    make_card <- function(title, color_cls, color_hex, stat) {
      div(class = paste("card border", color_cls, sep = "-"),
        div(class = "card-body p-3",
          h6(class = "card-title mb-2",
             style = paste0("color:", color_hex, "; font-weight:600;"), title),
          tags$table(class = "table table-sm table-borderless mb-0",
            tags$tbody(
              tags$tr(tags$td("N proteins"),    tags$td(strong(stat$n))),
              tags$tr(tags$td("Median ratio"),  tags$td(strong(stat$median_fc))),
              tags$tr(tags$td("% error"),       tags$td(strong(paste0(stat$pct_error, " %")))),
              tags$tr(tags$td("SD (log₂)"),     tags$td(strong(stat$sd_log2)))
            )
          )
        )
      )
    }

    fluidRow(
      column(4, make_card("HeLa (Homo sapiens)",    "success", "#00b050", s$H)),
      column(4, make_card("Yeast (Saccharomyces)",  "primary", "#6699ff", s$Y)),
      column(4, make_card("E. coli (Escherichia)",  "warning", "#cc6600", s$E))
    )
  })

  # ── Plot renders ──
  output$plot_combo <- renderPlot({ req(rv_plots$combo);  rv_plots$combo  })
  output$plot_ecoli <- renderPlot({ req(rv_plots$ecoli);  rv_plots$ecoli  })
  output$plot_hela  <- renderPlot({ req(rv_plots$hela);   rv_plots$hela   })
  output$plot_yeast <- renderPlot({ req(rv_plots$yeast);  rv_plots$yeast  })

  # ── Download helpers ──
  dl_handler <- function(plot_expr, base_name, width_mult = 1, height_mult = 1) {
    downloadHandler(
      filename = function() {
        paste0(base_name, "_", format(Sys.time(), "%Y%m%d_%H%M%S"),
               ".", input$dl_format)
      },
      content = function(file) {
        p <- plot_expr()
        req(p)
        ggsave(
          file,
          plot   = p,
          width  = input$dl_w * width_mult  / input$dl_dpi,
          height = input$dl_h * height_mult / input$dl_dpi,
          dpi    = input$dl_dpi,
          device = input$dl_format
        )
      }
    )
  }

  output$dl_scatter <- dl_handler(reactive(rv_plots$combo),
                                  "HYE_scatter_box_density")
  output$dl_ecoli   <- dl_handler(reactive(rv_plots$ecoli),
                                  "HYE_Scurves_Ecoli",  height_mult = 1.5)
  output$dl_hela    <- dl_handler(reactive(rv_plots$hela),
                                  "HYE_Scurves_HeLa",   height_mult = 1.5)
  output$dl_yeast   <- dl_handler(reactive(rv_plots$yeast),
                                  "HYE_Scurves_Yeast",  height_mult = 1.5)

  output$dl_all <- downloadHandler(
    filename = function() {
      paste0("HYE_AllPlots_", format(Sys.time(), "%Y%m%d_%H%M%S"),
             ".", input$dl_format)
    },
    content = function(file) {
      req(rv_plots$combo, rv_plots$ecoli, rv_plots$hela, rv_plots$yeast)
      combined <- rv_plots$combo /
        (rv_plots$ecoli | rv_plots$hela | rv_plots$yeast)
      ggsave(
        file,
        plot   = combined,
        width  = input$dl_w / input$dl_dpi,
        height = input$dl_h * 2.8 / input$dl_dpi,
        dpi    = input$dl_dpi,
        device = input$dl_format
      )
    }
  )
}

shinyApp(ui, server)
