library(tidyverse)

REQUIRED_COLS <- c(
  "R.Condition", "R.FileName", "R.Replicate", "PG.Organisms",
  "PG.ProteinAccessions", "PG.ProteinGroups",
  "PG.Qvalue", "PG.Quantity",
  "PEP.GroupingKey", "PEP.StrippedSequence", "PEP.Quantity",
  "EG.iRTPredicted", "EG.Library", "EG.ModifiedSequence",
  "EG.PrecursorId", "EG.Qvalue",
  "FG.Charge", "FG.Id", "FG.PrecMz",
  "FG.Quantity", "FG.MS1RawQuantity",
  "F.Charge", "F.FrgIon", "F.FrgLossType", "F.FrgMz",
  "F.FrgNum", "F.FrgType",
  "F.ExcludedFromQuantification", "F.PeakArea"
)

validate_columns <- function(data) {
  setdiff(REQUIRED_COLS, colnames(data))
}

rowSDs <- function(x, num_of_measurements) {
  sqrt(rowSums((x - rowMeans(x, na.rm = TRUE))^2, na.rm = TRUE) /
         (num_of_measurements - 1))
}

build_organism_map <- function(data) {
  list(
    H = data %>%
      filter(str_detect(PG.Organisms, "Homo sapiens") &
               !str_detect(PG.Organisms, "Saccharomyces|Escherichia")) %>%
      select(PG.ProteinGroups) %>% distinct(),
    Y = data %>%
      filter(str_detect(PG.Organisms, "Saccharomyces") &
               !str_detect(PG.Organisms, "Homo sapiens|Escherichia")) %>%
      select(PG.ProteinGroups) %>% distinct(),
    E = data %>%
      filter(str_detect(PG.Organisms, "Escherichia") &
               !str_detect(PG.Organisms, "Homo sapiens|Saccharomyces")) %>%
      select(PG.ProteinGroups) %>% distinct()
  )
}

add_organism_labels_pg <- function(pgdata, org_map) {
  bind_rows(
    semi_join(pgdata, org_map$H, by = "PG.ProteinGroups") %>% mutate(organism = "HELA"),
    semi_join(pgdata, org_map$Y, by = "PG.ProteinGroups") %>% mutate(organism = "YEAST"),
    semi_join(pgdata, org_map$E, by = "PG.ProteinGroups") %>% mutate(organism = "E.COLI")
  )
}

add_organism_labels_fg <- function(fgdata, org_map) {
  h <- org_map$H %>% rename(PROTEIN = PG.ProteinGroups)
  y <- org_map$Y %>% rename(PROTEIN = PG.ProteinGroups)
  e <- org_map$E %>% rename(PROTEIN = PG.ProteinGroups)
  bind_rows(
    semi_join(fgdata, h, by = "PROTEIN") %>% mutate(organism = "HELA"),
    semi_join(fgdata, y, by = "PROTEIN") %>% mutate(organism = "YEAST"),
    semi_join(fgdata, e, by = "PROTEIN") %>% mutate(organism = "E.COLI")
  )
}

normalize_by_hela <- function(long_data) {
  data_H <- long_data %>% filter(organism == "HELA")

  runmedians <- data_H %>%
    group_by(GROUP, replicate) %>%
    summarise(median_run = median(log2int, na.rm = TRUE), .groups = "drop")

  fracmedians <- data_H %>%
    group_by(FRACTION) %>%
    summarise(median_frac = median(log2int, na.rm = TRUE), .groups = "drop")

  long_data %>%
    left_join(runmedians, by = c("GROUP", "replicate")) %>%
    left_join(fracmedians, by = "FRACTION") %>%
    mutate(Normalized_log2int = log2int - median_run + median_frac)
}

build_ratio_summary <- function(long_norm, id_cols, rep_cols) {
  wide <- pivot_wider(
    long_norm,
    id_cols    = id_cols,
    names_from = "replicate",
    values_from = "Normalized_log2int"
  ) %>%
    mutate(mean_log2 = rowMeans(across(all_of(rep_cols)), na.rm = TRUE))

  pivot_wider(
    wide,
    id_cols    = setdiff(id_cols, "GROUP"),
    names_from = "GROUP",
    values_from = "mean_log2"
  ) %>%
    mutate(
      log2AB         = `MIX-A` - `MIX-B`,
      Abundance.MixA = 2^`MIX-A`,
      Abundance.MixB = 2^`MIX-B`,
      Abundance.Diff = Abundance.MixA / Abundance.MixB
    )
}

build_scurve_ranks <- function(fg4, org, sma_n = 150) {
  df_a <- fg4 %>% filter(organism == org, GROUP == "MIX-A") %>%
    select(PRECURSOR, PROTEIN, organism, mean_log2)
  df_b <- fg4 %>% filter(organism == org, GROUP == "MIX-B") %>%
    select(PRECURSOR, PROTEIN, organism, mean_log2)

  joined <- full_join(df_a, df_b,
                      by      = c("PRECURSOR", "PROTEIN", "organism"),
                      suffix  = c(".MIX-A", ".MIX-B")) %>%
    filter(!is.na(`mean_log2.MIX-A`) & !is.na(`mean_log2.MIX-B`)) %>%
    arrange(desc(`mean_log2.MIX-B`))

  if (nrow(joined) < sma_n) sma_n <- max(2, floor(nrow(joined) / 2))

  joined %>%
    mutate(
      SMA.A      = TTR::SMA(`mean_log2.MIX-A`, n = sma_n),
      SMA.B      = TTR::SMA(`mean_log2.MIX-B`, n = sma_n),
      SMA.diffAB = SMA.A - SMA.B,
      Rank.Order = seq_len(n())
    )
}

scurve_to_long <- function(sc_df) {
  bind_rows(
    sc_df %>%
      select(organism, PRECURSOR, Rank.Order, SMA.A, SMA.B, SMA.diffAB,
             mean = `mean_log2.MIX-A`) %>%
      mutate(GROUP = "MIX-A"),
    sc_df %>%
      select(organism, PRECURSOR, Rank.Order, SMA.A, SMA.B, SMA.diffAB,
             mean = `mean_log2.MIX-B`) %>%
      mutate(GROUP = "MIX-B")
  )
}

make_stats_table <- function(summary_df, ratio_H = 1, ratio_E = 0.25, ratio_Y = 2) {
  df <- summary_df %>% filter(!is.na(Abundance.Diff))

  calc <- function(org, expected) {
    d   <- df %>% filter(organism == org)
    med <- median(d$Abundance.Diff, na.rm = TRUE)
    data.frame(
      Organism        = org,
      N_proteins      = nrow(d),
      Median_Ratio    = round(med, 3),
      Expected_Ratio  = expected,
      Pct_Error       = round(abs(med - expected) / expected * 100, 2),
      SD_log2_ratio   = round(sd(d$log2AB, na.rm = TRUE), 3)
    )
  }

  bind_rows(
    calc("HELA",   ratio_H),
    calc("E.COLI", ratio_E),
    calc("YEAST",  ratio_Y)
  )
}
