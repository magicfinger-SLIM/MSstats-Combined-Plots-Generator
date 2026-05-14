library(ggplot2)
library(patchwork)
library(forcats)

ORG_COLORS <- c("E.COLI" = "#cc6600", "HELA" = "#00b050", "YEAST" = "#6699ff")
MIX_COLORS <- c("MIX-A" = "#e16462", "MIX-B" = "#7e03a8")

.theme_ratio <- function() {
  theme_minimal() +
    theme(
      panel.grid  = element_blank(),
      axis.line   = element_line(color = "black"),
      axis.text   = element_text(size = 13, color = "black"),
      axis.title  = element_text(size = 14),
      axis.ticks  = element_line(color = "black")
    )
}

.theme_scurve <- function() {
  theme_minimal() +
    theme(
      panel.grid  = element_blank(),
      axis.line   = element_line(color = "black"),
      axis.text   = element_text(size = 14, color = "black"),
      axis.title  = element_text(size = 14),
      axis.ticks  = element_line(color = "darkgray"),
      legend.title = element_text(size = 14),
      legend.text  = element_text(size = 13)
    )
}

make_ratio_plot <- function(summary_df,
                            ratio_H = 1, ratio_E = 0.25, ratio_Y = 2,
                            ylim    = c(-4, 5)) {
  df <- summary_df %>% filter(!is.na(Abundance.Diff))

  exp_h <- log2(ratio_H)
  exp_e <- log2(ratio_E)
  exp_y <- log2(ratio_Y)

  hlines <- data.frame(
    yint   = c(exp_h, exp_e, exp_y),
    colour = unname(ORG_COLORS[c("HELA", "E.COLI", "YEAST")])
  )

  # Scatter
  p1 <- ggplot(df, aes(x = `MIX-B`, y = log2AB, color = organism)) +
    .theme_ratio() +
    theme(legend.position = "none",
          plot.margin = unit(c(1, 0, 1, 1), "cm")) +
    geom_point(size = 0.7, alpha = 0.3) +
    scale_color_manual(values = ORG_COLORS) +
    scale_y_continuous(limits = ylim, expand = c(0, 0)) +
    scale_x_continuous(breaks = seq(6, 26, by = 2)) +
    xlab(expression("Log"[2] ~ "[MixB Abundance]")) +
    ylab(expression("Log"[2] ~ "ratio [MixA/MixB]")) +
    geom_hline(yintercept = hlines$yint, linetype = 2, color = hlines$colour)

  # Density
  fill_na <- setNames(rep(NA_character_, 3), names(ORG_COLORS))
  p3 <- ggplot(df, aes(y = log2AB, fill = organism, colour = organism)) +
    .theme_ratio() +
    theme(axis.text.y  = element_blank(),
          axis.title.y = element_blank(),
          axis.line.y  = element_blank(),
          legend.position = "none",
          plot.margin = unit(c(1, 0.5, 1, 0.5), "cm")) +
    geom_density(linewidth = 0.75, alpha = 0.4) +
    scale_y_continuous(limits = ylim, expand = c(0, 0)) +
    scale_x_continuous(breaks = c(0, 1, 2), expand = c(0, 0)) +
    xlab("density") +
    scale_fill_manual(values   = fill_na) +
    scale_color_manual(values  = ORG_COLORS) +
    geom_hline(yintercept = hlines$yint, linetype = 2, color = hlines$colour)

  # Boxplot
  p2 <- ggplot(df, aes(x = organism, y = log2AB, fill = organism)) +
    .theme_ratio() +
    theme(axis.text.y  = element_blank(),
          axis.title.y = element_blank(),
          axis.line.y  = element_blank(),
          axis.text.x  = element_text(size = 13),
          legend.title = element_text(size = 14),
          legend.text  = element_text(size = 13),
          plot.margin  = unit(c(1, 1, 1, 0), "cm")) +
    stat_boxplot(geom = "errorbar", width = 0.15) +
    geom_boxplot() +
    scale_fill_manual(values = ORG_COLORS) +
    scale_y_continuous(limits = ylim, expand = c(0, 0)) +
    scale_x_discrete(labels = c("E.COLI" = "E", "HELA" = "H", "YEAST" = "Y")) +
    ylab(expression("Log"[2] ~ "ratio [MixA/MixB]")) +
    geom_hline(yintercept = hlines$yint, linetype = 2, color = hlines$colour)

  p1 + p3 + p2 + plot_layout(widths = c(10, 2, 2))
}

make_scurve_plot <- function(scurve_long, org_label,
                             expected_ratio  = 1,
                             measured_color  = "#00b050",
                             y_limits_top    = c(7, 25),
                             y_limits_sma    = c(10, 25)) {
  data <- scurve_long %>%
    filter(organism == org_label) %>%
    mutate(
      GROUP       = fct_relevel(GROUP, "MIX-A", "MIX-B"),
      .draw_order = if (expected_ratio >= 1) {
        factor(GROUP, levels = c("MIX-A", "MIX-B"))
      } else {
        factor(GROUP, levels = c("MIX-B", "MIX-A"))
      }
    ) %>%
    arrange(.draw_order)

  exp_log2  <- log2(expected_ratio)
  diff_ylim <- c(exp_log2 - 1, exp_log2 + 1)

  p_top <- ggplot(data, aes(x = Rank.Order, y = mean, color = GROUP)) +
    .theme_scurve() +
    theme(plot.title   = element_text(size = 18),
          plot.margin  = unit(c(1, 0, 1, 0), "cm")) +
    geom_point(size = 0.5) +
    scale_x_continuous(expand = c(0, 0)) +
    scale_y_continuous(limits = y_limits_top, expand = c(0, 0)) +
    scale_color_manual(values = MIX_COLORS) +
    guides(color = guide_legend(override.aes = list(size = 3))) +
    xlab("Rank Order of Precursors in Mix B") +
    ylab(expression("Mean Log"[2] ~ "MS1 FG Int.")) +
    ggtitle(org_label)

  p_mid <- ggplot(data, aes(x = Rank.Order)) +
    .theme_scurve() +
    theme(plot.margin = unit(c(1, 0, 1, 0), "cm")) +
    geom_line(aes(y = SMA.A, color = "MIX-A"), linewidth = 1) +
    geom_line(aes(y = SMA.B, color = "MIX-B"), linewidth = 1) +
    scale_x_continuous(expand = c(0, 0)) +
    scale_y_continuous(limits = y_limits_sma, expand = c(0, 0)) +
    scale_color_manual(name = NULL, values = MIX_COLORS) +
    xlab("Rank Order of Precursors in Mix B") +
    ylab("Simple Moving Avg.")

  p_bot <- ggplot(data, aes(x = Rank.Order)) +
    .theme_scurve() +
    theme(plot.margin = unit(c(1, 0, 0, 0), "cm")) +
    geom_hline(aes(yintercept = exp_log2, linetype = "Expected"),
               color = "black", linewidth = 1) +
    geom_line(aes(y = SMA.diffAB, color = "Measured"), linewidth = 1) +
    scale_x_continuous(expand = c(0, 0)) +
    scale_color_manual(name = NULL, values = c("Measured" = measured_color)) +
    scale_linetype_manual(name = NULL, values = c("Expected" = "solid")) +
    guides(color    = guide_legend(override.aes = list(linewidth = 1.5)),
           linetype = guide_legend(order = 2)) +
    ylim(diff_ylim) +
    xlab("Rank Order of Precursors in Mix B") +
    ylab(expression("Log"[2] ~ "Ratio [MixA/MixB]"))

  p_top / p_mid / p_bot + plot_layout(guides = "keep")
}

make_cv_plot <- function(cv_long, cv_col = "PG.CV") {
  if (!cv_col %in% colnames(cv_long)) return(NULL)

  cv_long %>%
    filter(!is.na(.data[[cv_col]]), .data[[cv_col]] <= 200) %>%
    rename(CV = all_of(cv_col)) %>%
    ggplot(aes(x = CV, fill = organism, color = organism)) +
    .theme_ratio() +
    geom_density(alpha = 0.4, linewidth = 0.75) +
    scale_fill_manual(values  = ORG_COLORS) +
    scale_color_manual(values = ORG_COLORS) +
    scale_x_continuous(limits = c(0, 100), expand = c(0, 0)) +
    xlab("CV (%)") + ylab("Density") +
    labs(fill = "Organism", color = "Organism")
}
