# Allow uploads up to 5 GB
options(shiny.maxRequestSize = 5 * 1024^3)

# MSstats HYE Mix Ratio Plot Generator
# Input: Spectronaut report (.tsv or .csv)
# Generates: Scatter/Box/Density plots + S-curve plots for HeLa, Yeast, E.coli

APP_VERSION <- "1.5.2"
APP_DATE    <- "2026-05-14"

# ── Changelog ─────────────────────────────────────────────────────────────────
# Add a new entry here whenever a version is released.
# Fields: version, date, type ("new" | "fix" | "improved"), description
CHANGELOG <- list(
  list(
    version = "1.5.2", date = "2026-05-14",
    changes = list(
      list(type = "fix", text = "Condition detector: tokens with trailing sequential numeric suffixes (e.g. '10dB-0001', '10dB-0002') are now normalised by stripping the '-N' suffix before column classification, so instrument/replicate index tokens no longer generate spurious extra conditions")
    )
  ),
  list(
    version = "1.5.1", date = "2026-05-14",
    changes = list(
      list(type = "fix", text = "Condition detector: per-run tokens whose values are all unique across files (e.g. date-time strings like '2026-05-06-14.48.21-100ng') are now correctly classified as run identifiers, not conditions — prevents each file from getting its own spurious condition label"),
      list(type = "fix", text = "Filename-based R.Condition override is now applied to raw data before data_filt is constructed, so MSstats always receives the corrected condition labels")
    )
  ),
  list(
    version = "1.5.0", date = "2026-05-14",
    changes = list(
      list(type = "new",      text = "Plot label inputs: customise what appears in axes and legends for Mix A and Mix B (default: MIX-A / MIX-B)"),
      list(type = "improved", text = "Scatter/box/density axes now show the user-defined labels instead of the raw condition token"),
      list(type = "improved", text = "S-curve panel legends and ratio axis now show the user-defined labels instead of the raw condition token")
    )
  ),
  list(
    version = "1.4.0", date = "2026-05-14",
    changes = list(
      list(type = "fix",      text = "Removed n_max limit — all R.FileName rows are now read, so no files are missed"),
      list(type = "fix",      text = "Condition detection now completely independent of R.Condition column"),
      list(type = "improved", text = "Filename-derived condition labels (e.g. E5H50Y45) override R.Condition in the pipeline, ensuring correct MSstats grouping regardless of how R.Condition is set in Spectronaut"),
      list(type = "improved", text = "Replicate numbers derived from filename tokens (e.g. A1 → 1) also override R.Replicate"),
      list(type = "improved", text = "Sidebar description updated: now clearly states detection is from R.FileName")
    )
  ),
  list(
    version = "1.3.0", date = "2026-05-14",
    changes = list(
      list(type = "new",      text = "Auto-detect conditions from R.FileName token parsing"),
      list(type = "new",      text = "Token matrix classifies filename parts as timestamp / replicate / condition automatically"),
      list(type = "new",      text = "Condition dropdown labels show detected token + [N reps, N files]"),
      list(type = "new",      text = "Detection summary table in sidebar showing mapping and example filenames"),
      list(type = "improved", text = "Fallback to R.Condition values if filename parsing is inconclusive")
    )
  ),
  list(
    version = "1.2.0", date = "2026-05-14",
    changes = list(
      list(type = "new",      text = "Condition inputs replaced with auto-populated dropdowns (selectInput)"),
      list(type = "new",      text = "Conditions detected from R.Condition on file upload — no manual typing needed"),
      list(type = "fix",      text = "Guard added: Mix-A and Mix-B cannot be assigned the same condition"),
      list(type = "improved", text = "Error messages now list available condition names when label is not found")
    )
  ),
  list(
    version = "1.1.0", date = "2026-05-14",
    changes = list(
      list(type = "new",      text = "Auto-detect replicate count from R.Replicate column on file upload"),
      list(type = "new",      text = "Replicate labels derived from MSstats SUBJECT column (not hardcoded 1..N)"),
      list(type = "improved", text = "Sidebar n_reps defaults to 0 (auto-detect); manual override still supported"),
      list(type = "fix",      text = "Fixed 'Column MIX-A not found' crash when replicate count did not match default of 4"),
      list(type = "fix",      text = "MS2 mode: duplicate fragments per precursor now collapsed with mean before pivoting")
    )
  ),
  list(
    version = "1.0.0", date = "2026-05-13",
    changes = list(
      list(type = "new", text = "Initial release"),
      list(type = "new", text = "Spectronaut .tsv / .csv input up to 5 GB"),
      list(type = "new", text = "MS1 precursor (FG.MS1RawQuantity) and MS2 fragment (F.PeakArea) modes"),
      list(type = "new", text = "Full MSstats pipeline: SpectronauttoMSstatsFormat → dataProcess (TMP, no norm, no imputation)"),
      list(type = "new", text = "Species assignment for HeLa / Yeast / E.coli via PG.Organisms"),
      list(type = "new", text = "HeLa-median run normalisation applied to all species"),
      list(type = "new", text = "Scatter + Box + Density combined plot with per-species statistics cards"),
      list(type = "new", text = "S-curve plots (rank-ordered, SMA window = 150) for E.coli, HeLa, and Yeast"),
      list(type = "new", text = "Download: PNG / PDF / SVG with configurable pixel size and DPI"),
      list(type = "new", text = "Optional pre-saved .rda MSstats summary to skip slow dataProcess step"),
      list(type = "new", text = "About tab with full pipeline and column documentation"),
      list(type = "new", text = "Source Code tab with annotated sections and highlight.js syntax highlighting")
    )
  )
)

# Read own source at startup for the Source Code tab.
# Shiny automatically sets the working directory to the app folder.
app_src_lines <- tryCatch(readLines("app.R", warn = FALSE), error = function(e) character(0))

# Section definitions: pattern matches the first line of each section,
# title is the display heading, desc is the plain-English explanation.
.src_sections <- list(
  list(pat = "^options\\(shiny",
       title = "1 · Upload Limit & Package Loading",
       desc  = paste(
         "Raises Shiny's default 5 MB upload cap to 5 GB so large Spectronaut",
         "reports can be loaded directly. Then silently loads five packages:",
         "shiny and bslib provide the reactive UI framework;",
         "tidyverse (dplyr, tidyr, stringr, readr) handles all data wrangling;",
         "ggplot2 builds every plot; patchwork assembles multi-panel figures."
       )),
  list(pat = "^APP_VERSION",
       title = "2 · Version Constants",
       desc  = paste(
         "APP_VERSION and APP_DATE are module-level constants that propagate",
         "automatically into the navbar title badge and the About tab footer.",
         "Releasing a new version only requires editing these two lines."
       )),
  list(pat = "^# ── UI",
       title = "3 · Page Layout — Root UI",
       desc  = paste(
         "page_sidebar() from bslib creates the two-column layout: a fixed left",
         "sidebar for controls and a right main area for plots.",
         "bs_theme(bootswatch='flatly') applies the Bootstrap 5 Flatly theme and",
         "loads the Inter typeface from Google Fonts.",
         "The version badge is injected inline into the title via tags$span/tags$small.",
         "highlight.js is loaded from CDN via tags$head() for R syntax colouring",
         "in the Source Code tab; a jQuery hook re-runs hljs after each Shiny render."
       )),
  list(pat = "^    # ── Input ──",
       title = "4 · Sidebar — Control Panels",
       desc  = paste(
         "An accordion with four collapsible panels.",
         "Upload Data: fileInput() for the Spectronaut .tsv/.csv (up to 5 GB) and",
         "an optional pre-saved .rda MSstats summary to skip the slow dataProcess step;",
         "radio buttons switch between MS1 (FG.MS1RawQuantity) and MS2 (F.PeakArea) modes.",
         "Condition Names: text inputs for MixA/MixB labels exactly as they appear in",
         "R.Condition (case-sensitive), plus the required replicate count.",
         "Expected Log2 Ratios: per-species numeric inputs for the dashed reference lines.",
         "Download Options: format (PNG/PDF/SVG), pixel width/height, DPI,",
         "and one download button per output plot."
       )),
  list(pat = "^  # ── Main panel ──",
       title = "5 · Main Panel — Output Tabs",
       desc  = paste(
         "navset_tab() defines seven output tabs:",
         "Scatter/Box/Density shows the three-panel combined ratio plot with species",
         "statistics cards rendered above via uiOutput().",
         "Three S-Curves tabs (E.coli/HeLa/Yeast) show rank-ordered precursor plots.",
         "Log displays timestamped processing messages from the current run.",
         "Source Code (this tab) shows the annotated app source with highlight.js.",
         "The ⓘ icon tab is the full About/documentation panel."
       )),
  list(pat = "^# ── Server",
       title = "6 · Server — Initialisation",
       desc  = paste(
         "Opens the Shiny server function. rv_log (reactiveVal) accumulates",
         "timestamped text lines rendered in the Log tab.",
         "rv_plots (reactiveValues) stores four ggplot objects",
         "(combo, ecoli, hela, yeast) and a stats list; all start as NULL and are",
         "populated only after the user clicks Generate Plots.",
         "log_msg() appends a formatted timestamp to rv_log and echoes to the R console."
       )),
  list(pat = "^  # ── Helper: row SD",
       title = "7 · Helper — row_sds()",
       desc  = paste(
         "Computes the sample standard deviation row-wise across a numeric matrix,",
         "handling NAs. Formula: sqrt(rowSums((x − rowMeans(x))², na.rm=TRUE) / (n−1)).",
         "Used to calculate the coefficient of variation (CV) for each protein or",
         "precursor across replicates before the completeness filter is applied."
       )),
  list(pat = "^  # ── Helper: assign organism",
       title = "8 · Helper — make_uniprot_sets()",
       desc  = paste(
         "Builds three exclusive protein-accession sets (H, Y, E) by filtering the",
         "PG.Organisms column of the raw Spectronaut data with str_detect().",
         "Strict exclusion logic prevents proteins shared between species",
         "(contaminants, iRT standards) from appearing in more than one set.",
         "The resulting tibbles are used with semi_join() to label MSstats proteins",
         "as HELA, YEAST, or E.COLI."
       )),
  list(pat = "^  # ── Helper: HeLa-based",
       title = "9 · Helper — normalize_by_hela()",
       desc  = paste(
         "Implements HeLa-median run normalisation.",
         "Step 1: for each (condition × replicate) run, compute the median log₂",
         "intensity of HeLa proteins.",
         "Step 2: compute one experiment-wide median across all HeLa runs.",
         "Step 3: Normalised value = raw log₂ − run_median + experiment_median.",
         "This corrects systematic run-to-run loading variation while preserving",
         "the biologically expected mixing ratios for Yeast and E.coli."
       )),
  list(pat = "^  # ── Helper: scatter \\+ box",
       title = "10 · Helper — make_combo_plot()",
       desc  = paste(
         "Builds the three-panel ratio overview figure.",
         "p1 (scatter): log₂ ratio (MixA/MixB) on y vs MixB mean abundance on x,",
         "coloured by species, with dashed reference lines at expected ratios.",
         "p3 (density): horizontal kernel density curves sharing y-axis limits with p1.",
         "p2 (box plot): species-level box-and-whisker plots.",
         "patchwork assembles them at widths 10:2:2 so the scatter dominates.",
         "Y-axis limits are clamped to the 0.5th–99.5th percentile to exclude outliers."
       )),
  list(pat = "^  # ── Helper: S-curve",
       title = "11 · Helper — make_scurve_plot()",
       desc  = paste(
         "Generates the three-panel S-curve plot for one species.",
         "Precursors present in both MixA and MixB are full-joined, then ranked",
         "in descending order of MixB mean intensity.",
         "TTR::SMA() applies a 150-precursor simple moving average to both traces.",
         "Panel pa: raw per-precursor scatter for MixA and MixB.",
         "Panel pb: SMA smoothed traces for both conditions.",
         "Panel pc: SMA(A) − SMA(B) difference curve vs the expected log₂ ratio.",
         "All three panels are stacked vertically with patchwork."
       )),
  list(pat = "^  # ── Main processing",
       title = "12 · Main Pipeline — observeEvent(input$run)",
       desc  = paste(
         "The core event handler, triggered by the Generate Plots button.",
         "Wrapped in withProgress() for a live progress bar and tryCatch() for",
         "user-friendly error notifications.",
         "Step 1: optionally load a pre-saved .rda to skip dataProcess.",
         "Step 2: read and validate the Spectronaut file; check all 29 required columns.",
         "Step 3: reformat for MSstats and apply mode-specific column remapping",
         "(MS1 overwrites F.PeakArea ← FG.MS1RawQuantity; MS2 uses F.PeakArea as-is).",
         "Step 4: SpectronauttoMSstatsFormat() then dataProcess().",
         "Step 5: protein level — assign species, pivot wide, filter to complete",
         "replicates, apply HeLa normalisation, compute ratios, build combo plot.",
         "Step 6: feature level — same pipeline for S-curve data; mean-collapse",
         "duplicate fragments (MS2) with values_fn=mean in pivot_wider.",
         "Step 7: call make_scurve_plot() for each species; store all in rv_plots."
       )),
  list(pat = "^  # ── Statistics cards",
       title = "13 · Output — Statistics Cards (output$stats_cards)",
       desc  = paste(
         "Renders three Bootstrap info cards above the scatter plot via renderUI().",
         "Each card reports for one species:",
         "N — number of proteins passing the complete-replicates filter;",
         "Median fold-change — linear-scale median of MixA/MixB ratios;",
         "% error — deviation of the median from the expected fold-change;",
         "SD (log₂) — standard deviation of the log₂ ratio distribution,",
         "a direct measure of quantification precision."
       )),
  list(pat = "^  # ── Plot renders",
       title = "14 · Output — Plot Renders & Download Handlers",
       desc  = paste(
         "Four renderPlot() calls bind rv_plots ggplot objects to their UI outputs,",
         "gated with req() so they fail gracefully if plots are not yet generated.",
         "dl_handler() is a factory function that returns a downloadHandler();",
         "ggsave() converts pixel dimensions to inches by dividing by DPI.",
         "Individual buttons save one plot; the combined download stacks the scatter",
         "panel above the three S-curve panels (patchwork | and /) at 2.8× height.",
         "The source code tab output (output$source_code_ui) renders here too,",
         "reading app_src_lines and splitting by the # ── section markers."
       )),
  list(pat = "^shinyApp",
       title = "15 · App Entry Point — shinyApp()",
       desc  = paste(
         "Passes the completed ui and server definitions to the Shiny runtime.",
         "When executed via shiny::runApp() or the RStudio Run App button,",
         "Shiny starts a local HTTP server, binds the full reactive dependency graph,",
         "and opens the app in the system default browser."
       ))
)

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

  tags$head(
    tags$link(
      rel  = "stylesheet",
      href = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/atom-one-light.min.css"
    ),
    tags$script(
      src = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"
    ),
    # Re-run highlight.js each time Shiny pushes new content to the DOM
    tags$script(HTML(
      "$(document).on('shiny:value', function() {",
      "  setTimeout(function() {",
      "    document.querySelectorAll('pre code').forEach(function(el) {",
      "      hljs.highlightElement(el);",
      "    });",
      "  }, 150);",
      "});"
    ))
  ),

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
        "2  Condition Assignment", id = "p2",
        tags$small(class = "text-muted d-block mb-2",
          icon("circle-info"), " Upload a file first — conditions and replicates are auto-detected from ",
          tags$code("R.FileName"), "."),
        selectInput("mixa_name", "Assign to Mix A", choices = character(0)),
        selectInput("mixb_name", "Assign to Mix B", choices = character(0)),
        fluidRow(
          column(6, textInput("mixa_label", "Mix A plot label", value = "MIX-A")),
          column(6, textInput("mixb_label", "Mix B plot label", value = "MIX-B"))
        ),
        numericInput("n_reps", "Min. replicates required (0 = auto-detect)",
                     value = 0, min = 0, max = 20),
        uiOutput("detected_design_ui")
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
      "Source Code",
      br(),
      uiOutput("source_code_ui")
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

          # ── Changelog ──
          div(class = "card mb-4",
            div(class = "card-header fw-bold", icon("clock-rotate-left"), " Version History"),
            div(class = "card-body p-0",
              tagList(lapply(CHANGELOG, function(v) {
                is_latest <- v$version == APP_VERSION
                badge_cls <- if (is_latest) "bg-success" else "bg-secondary"

                type_icon <- function(t) switch(t,
                  new      = tags$span(class = "badge bg-primary me-1",   "NEW"),
                  fix      = tags$span(class = "badge bg-danger me-1",    "FIX"),
                  improved = tags$span(class = "badge bg-warning text-dark me-1", "IMPROVED"),
                  tags$span(class = "badge bg-secondary me-1", toupper(t))
                )

                div(class = if (is_latest) "p-3 border-bottom bg-light" else "p-3 border-bottom",
                  div(class = "d-flex align-items-center gap-2 mb-2",
                    tags$span(class = paste("badge fs-6", badge_cls),
                              paste0("v", v$version)),
                    tags$span(class = "text-muted small", v$date),
                    if (is_latest) tags$span(class = "badge bg-success-subtle text-success border border-success-subtle",
                                             "current") else NULL
                  ),
                  tags$ul(class = "mb-0 ps-3",
                    lapply(v$changes, function(ch) {
                      tags$li(class = "mb-1", type_icon(ch$type), ch$text)
                    })
                  )
                )
              }))
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

# ── Filename design detector ──────────────────────────────────────────────────
# Parses R.FileName tokens to identify condition labels and replicate numbers.
# Completely independent of R.Condition.
# Strategy:
#   1. Take unique R.FileName values (all rows, not a sample)
#   2. Strip path + extension, split each filename on "_"
#   3. Build a token matrix (rows = files, cols = token positions)
#   4. Keep only columns that VARY across files
#   5. Classify each variable column:
#        timestamp  — 6+ consecutive digits (dates/times like 20260512, 140056)
#        replicate  — optional letters then digits (A1, rep3, B2, 1, 2, ...)
#        condition  — everything else (E5H50Y45, E45H50Y5, ...)
#   6. Paste condition tokens per file → condition label
#   7. Extract numeric part of replicate token → replicate integer
detect_design_from_filenames <- function(unique_fns) {
  # Normalise: basename only, strip extension
  clean    <- tools::file_path_sans_ext(basename(unique_fns))

  # Tokenise on underscore
  tok_list <- strsplit(clean, "_")
  max_n    <- max(lengths(tok_list))
  tok_mat  <- t(sapply(tok_list, function(x)
    c(x, rep(NA_character_, max_n - length(x)))))
  rownames(tok_mat) <- unique_fns

  # Normalise tokens: strip trailing sequential numeric suffixes like "-0001",
  # "-002", "-1" so that "10dB-0001" and "10dB-0002" both become "10dB".
  # This prevents instrument/run index tokens from appearing as distinct
  # conditions when the base part (e.g. "10dB") is constant across files.
  norm_mat <- apply(tok_mat, 2, function(col)
    sub("-\\d{1,6}$", "", col))

  # Keep only columns that differ across files (using normalised values)
  var_mask <- apply(norm_mat, 2, function(col) length(unique(na.omit(col))) > 1)
  if (!any(var_mask)) return(NULL)
  var_mat  <- norm_mat[, var_mask, drop = FALSE]

  # Classify each variable column.
  # Order matters: check pure-digit timestamps first (so large digit strings
  # aren't grabbed by is_rep), then replicate patterns, then the all-unique
  # heuristic (per-run identifiers like "2026-05-06-14.48.21-100ng" are all
  # unique across files even though they contain letters and separators).
  is_ts_digits <- function(x) all(grepl("^\\d{6,}$", na.omit(x)))
  is_rep       <- function(x) all(grepl("^[A-Za-z]{0,4}\\d+$", na.omit(x)))
  is_ts_unique <- function(x) {
    x <- na.omit(x)
    length(x) > 1 && length(unique(x)) == length(x)
  }

  col_type <- apply(var_mat, 2, function(col) {
    if (is_ts_digits(col)) return("ts")   # pure digit date/time stamps
    if (is_rep(col))       return("rep")  # letter-prefix + digit rep labels
    if (is_ts_unique(col)) return("ts")   # all unique → per-run identifier
    return("cond")
  })

  cond_mat <- var_mat[, col_type == "cond", drop = FALSE]
  rep_mat  <- var_mat[, col_type == "rep",  drop = FALSE]

  # Fallback: if nothing qualifies as condition, use all non-timestamp tokens
  if (ncol(cond_mat) == 0)
    cond_mat <- var_mat[, col_type != "ts", drop = FALSE]

  # Build per-file condition label by pasting condition tokens
  fn_cond <- if (ncol(cond_mat) > 0)
    apply(cond_mat, 1, function(r) paste(na.omit(r), collapse = "_"))
  else
    rep("unknown", nrow(var_mat))

  # Extract replicate integer from replicate token (last numeric run)
  fn_rep <- if (ncol(rep_mat) > 0)
    suppressWarnings(apply(rep_mat, 1, function(r) {
      r <- na.omit(r)
      if (length(r) == 0) return(NA_integer_)
      as.integer(gsub("[^0-9]", "", r[length(r)]))
    }))
  else
    NA_integer_

  tibble(
    R.FileName   = unique_fns,
    fn_condition = fn_cond,
    fn_replicate = as.integer(fn_rep)
  )
}

# ── Server ────────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  # ── Reactive log ──
  rv_log   <- reactiveVal(character(0))
  rv_fn_map <- reactiveVal(NULL)          # filename → condition/replicate mapping
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
  make_combo_plot <- function(df, mixb_col, ratio_H, ratio_Y, ratio_E,
                               mixa_label = "MIX-A", mixb_label = "MIX-B") {
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
      xlab(bquote(Log[2] ~ .(paste0("[", mixb_label, " Protein Abundance]")))) +
      ylab(bquote(Log[2] ~ .(paste0("ratio [", mixa_label, "/", mixb_label, "]")))) +
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
      ylab(bquote(Log[2] ~ .(paste0("ratio [", mixa_label, "/", mixb_label, "]")))) +
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
                                expected_ratio, mixa, mixb, sma_n = 150,
                                mixa_label = "MIX-A", mixb_label = "MIX-B") {
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
      joined %>% mutate(mean = mean_log2.A, GROUP = mixa_label),
      joined %>% mutate(mean = mean_log2.B, GROUP = mixb_label)
    ) %>% mutate(GROUP = factor(GROUP, levels = c(mixa_label, mixb_label)))

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
      scale_color_manual(values = setNames(c("#e16462", "#7e03a8"), c(mixa_label, mixb_label))) +
      guides(color = guide_legend(override.aes = list(size = 3))) +
      xlab("Rank Order of Precursors in Mix B") +
      ylab(expression("Mean Log"[2] ~ "Intensity")) +
      ggtitle(org_label)

    pb <- ggplot(joined, aes(x = Rank)) +
      sc_theme +
      theme(plot.margin = unit(c(1, 0, 1, 0), "cm")) +
      geom_line(aes(y = SMA.A, color = mixa_label), linewidth = 1) +
      geom_line(aes(y = SMA.B, color = mixb_label), linewidth = 1) +
      scale_x_continuous(expand = c(0, 0)) +
      scale_color_manual(name = NULL,
                         values = setNames(c("#e16462", "#7e03a8"), c(mixa_label, mixb_label))) +
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
      ylab(bquote(Log[2] ~ .(paste0("Ratio [", mixa_label, "/", mixb_label, "]"))))

    pa / pb / pc + plot_layout(guides = "keep")
  }

  # ── Auto-populate condition dropdowns on file upload ──
  observeEvent(input$file, {
    req(input$file)

    ext     <- tools::file_ext(input$file$name)
    read_fn <- if (ext == "tsv") read_tsv else read_csv

    # Read ONLY R.FileName — all rows, no n_max limit.
    # readr reads one column much faster than the whole file even for 5 GB.
    fn_col <- tryCatch(
      read_fn(input$file$datapath,
              col_select     = "R.FileName",
              show_col_types = FALSE),
      error = function(e) NULL
    )

    if (is.null(fn_col) || nrow(fn_col) == 0) {
      showNotification("Could not read R.FileName from file.", type = "warning")
      return()
    }

    unique_fns <- unique(fn_col$R.FileName)

    # Parse filenames — completely independent of R.Condition
    fn_map <- tryCatch(
      detect_design_from_filenames(unique_fns),
      error = function(e) NULL
    )

    if (is.null(fn_map) || n_distinct(fn_map$fn_condition) < 1) {
      showNotification("Could not detect conditions from R.FileName. Check filename format.",
                       type = "error", duration = 8)
      return()
    }

    # Store mapping — pipeline will use it to override R.Condition
    rv_fn_map(fn_map)

    # Summarise per detected condition (R.FileName parsing only)
    s <- fn_map %>%
      group_by(fn_condition) %>%
      summarise(
        n_files = n(),
        n_reps  = n_distinct(fn_replicate[!is.na(fn_replicate)]),
        example = basename(first(R.FileName)),
        .groups = "drop"
      ) %>%
      arrange(fn_condition)

    if (nrow(s) < 2)
      showNotification(
        paste0("Only 1 condition detected. Verify that filenames differ between conditions."),
        type = "warning", duration = 8
      )

    # Dropdown value AND label = fn_condition (no R.Condition dependency)
    choices <- setNames(
      s$fn_condition,
      paste0(s$fn_condition, "  [", s$n_reps, " reps · ", s$n_files, " files]")
    )

    updateSelectInput(session, "mixa_name", choices = choices,
                      selected = s$fn_condition[1])
    updateSelectInput(session, "mixb_name", choices = choices,
                      selected = if (nrow(s) > 1) s$fn_condition[2] else s$fn_condition[1])

    n_reps_det <- max(s$n_reps, na.rm = TRUE)
    if (!is.na(n_reps_det) && n_reps_det > 0)
      updateNumericInput(session, "n_reps", value = n_reps_det)

    # Sidebar detection table
    output$detected_design_ui <- renderUI({
      rows <- lapply(seq_len(nrow(s)), function(i) {
        tags$tr(
          tags$td(tags$code(s$fn_condition[i])),
          tags$td(style = "font-size:0.8em; color:#555;", s$example[i]),
          tags$td(class = "text-center", s$n_reps[i]),
          tags$td(class = "text-center", s$n_files[i])
        )
      })
      div(class = "mt-2",
        tags$table(class = "table table-sm table-bordered mb-0",
          style = "font-size:0.8em;",
          tags$thead(class = "table-light",
            tags$tr(tags$th("Condition from filename"), tags$th("Example file"),
                    tags$th("Reps"), tags$th("Files"))
          ),
          tags$tbody(rows)
        )
      )
    })

    showNotification(
      paste0("Detected ", nrow(s), " condition(s) from R.FileName ",
             "(", length(unique_fns), " unique files)."),
      type = "message", duration = 5
    )
  })

  # ── Main processing ──
  observeEvent(input$run, {

    # Reset
    rv_log(character(0))
    rv_plots$combo <- rv_plots$ecoli <- rv_plots$hela <-
      rv_plots$yeast <- rv_plots$stats <- NULL

    mixa   <- trimws(input$mixa_name)
    mixb   <- trimws(input$mixb_name)

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

        # ── Step 2: Apply filename-based override FIRST, then build data_filt ──
        # Override must happen before data_filt is constructed so that
        # SpectronauttoMSstatsFormat() receives the corrected R.Condition values.
        fn_map_val <- rv_fn_map()
        if (!is.null(fn_map_val)) {
          raw <- raw %>%
            left_join(fn_map_val, by = "R.FileName") %>%
            mutate(
              R.Condition = fn_condition,
              R.Replicate = if_else(!is.na(fn_replicate),
                                    as.integer(fn_replicate),
                                    as.integer(R.Replicate))
            ) %>%
            select(-fn_condition, -fn_replicate)
          log_msg(paste0("R.Condition overridden from R.FileName: ",
                         paste(sort(unique(raw$R.Condition)), collapse = ", ")))
          log_msg(paste0("R.Replicate range: ",
                         min(raw$R.Replicate, na.rm = TRUE), " – ",
                         max(raw$R.Replicate, na.rm = TRUE)))
        }

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

        # ── Auto-detect experimental design ──
        detected_conditions <- sort(unique(raw$R.Condition))
        detected_reps       <- length(unique(raw$R.Replicate))

        log_msg(paste0("Detected conditions: ", paste(detected_conditions, collapse = ", ")))
        log_msg(paste0("Detected replicates per condition: ", detected_reps))

        # Validate condition assignments
        if (mixa == mixb)
          stop("Mix A and Mix B are assigned to the same condition. Please select two different conditions.")
        if (!mixa %in% detected_conditions)
          stop(paste0("Mix-A condition '", mixa, "' not found in R.Condition. ",
                      "Available: ", paste(detected_conditions, collapse = ", ")))
        if (!mixb %in% detected_conditions)
          stop(paste0("Mix-B condition '", mixb, "' not found in R.Condition. ",
                      "Available: ", paste(detected_conditions, collapse = ", ")))

        # Use auto-detected replicate count unless user overrides (n_reps > 0)
        n_reps <- if (input$n_reps > 0) input$n_reps else detected_reps
        if (input$n_reps > 0 && input$n_reps != detected_reps)
          log_msg(paste0("NOTE: replicate override set to ", n_reps,
                         " (auto-detected: ", detected_reps, ")"))

        # Update sidebar display
        output$detected_design_ui <- renderUI({
          div(class = "alert alert-info p-2 mt-2 mb-0 small",
            icon("circle-check"), " ",
            strong("Auto-detected:"), br(),
            paste0(length(detected_conditions), " conditions: ",
                   paste(detected_conditions, collapse = ", ")), br(),
            paste0(n_reps, " replicates per condition")
          )
        })
        updateNumericInput(session, "n_reps", value = n_reps)

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

        # Derive replicate labels directly from the MSstats output (ground truth)
        rep_cols <- sort(as.character(unique(mss$ProteinLevelData$SUBJECT)))
        n_reps   <- length(rep_cols)
        log_msg(paste0("MSstats SUBJECT labels: ", paste(rep_cols, collapse = ", "),
                       "  (", n_reps, " replicates)"))

        # Pivot to wide → compute measurements
        PGdata_wide <- pivot_wider(
          PGdata_sp,
          id_cols    = c("Protein", "organism", "GROUP"),
          names_from = "SUBJECT", values_from = "LogIntensities",
          values_fn  = \(x) mean(x, na.rm = TRUE)
        )

        PGdata_wide <- PGdata_wide %>%
          mutate(n_meas = rowSums(!is.na(across(all_of(rep_cols)))))

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
        rv_plots$combo <- make_combo_plot(df_pg, mixb, ratio_H, ratio_Y, ratio_E,
                                           mixa_label = input$mixa_label,
                                           mixb_label = input$mixb_label)

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
        if (length(avail_rep_cols) == 0)
          stop("No replicate columns found in feature-level data after pivoting.")

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
                                            "#cc6600", ratio_E, mixa, mixb,
                                            mixa_label = input$mixa_label,
                                            mixb_label = input$mixb_label)
        rv_plots$hela  <- make_scurve_plot(FGdata_4, "HELA",   "HeLa",
                                            "#00b050", ratio_H, mixa, mixb,
                                            mixa_label = input$mixa_label,
                                            mixb_label = input$mixb_label)
        rv_plots$yeast <- make_scurve_plot(FGdata_4, "YEAST",  "Yeast",
                                            "#6699ff", ratio_Y, mixa, mixb,
                                            mixa_label = input$mixa_label,
                                            mixb_label = input$mixb_label)

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

  # ── Source Code tab ──
  output$source_code_ui <- renderUI({

    if (length(app_src_lines) == 0) {
      return(div(class = "alert alert-warning m-3",
                 "Source file could not be read. Make sure app.R is in the working directory."))
    }

    # Find where each section starts by matching the grep pattern
    find_start <- function(pat) {
      idx <- grep(pat, app_src_lines, perl = TRUE)
      if (length(idx) == 0) NA_integer_ else idx[1]
    }

    starts <- vapply(.src_sections, function(s) find_start(s$pat), integer(1))

    # Each section runs from its start to one line before the next section start
    n_src   <- length(app_src_lines)
    ends    <- c(starts[-1] - 1L, n_src)

    # Build one card per section
    cards <- mapply(function(sec, start, end) {

      if (is.na(start)) return(NULL)
      code_block <- paste(app_src_lines[start:end], collapse = "\n")

      div(class = "card mb-4 shadow-sm",
        div(class = "card-header d-flex align-items-center gap-2 fw-semibold bg-light",
            tags$span(class = "badge bg-primary me-1",
                      strsplit(sec$title, " ·")[[1]][1]),
            sub("^\\d+ · ", "", sec$title)
        ),
        div(class = "card-body pb-1",
          p(class = "text-secondary", sec$desc),
          tags$pre(
            class = "rounded border bg-white p-0 mb-0",
            style = "font-size:0.78em; max-height:420px; overflow:auto;",
            tags$code(
              class = "language-r",
              style = "background:transparent;",
              code_block
            )
          )
        )
      )
    }, .src_sections, starts, ends, SIMPLIFY = FALSE)

    fluidRow(
      column(10, offset = 1,
        div(class = "alert alert-info mb-4",
          icon("code"), " ",
          strong(paste0("MSstats HYE Plot Generator — Source Code  v", APP_VERSION)),
          " · ",
          nchar(paste(app_src_lines, collapse = "")) |> format(big.mark = ","),
          " characters · ",
          length(app_src_lines) |> format(big.mark = ","),
          " lines · ",
          length(.src_sections), " annotated sections"
        ),
        tagList(Filter(Negate(is.null), cards))
      )
    )
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
