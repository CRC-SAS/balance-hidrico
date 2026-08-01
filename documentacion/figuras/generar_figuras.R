#!/usr/bin/env Rscript
# Genera las figuras de documentacion/PAPER.md a partir del escenario de
# referencia real (trigo, estacion 87480, siembra 1983-05-30, suelo
# IN64MARC02) -- mismos datos que usan los tests del paquete.
#
# Uso (desde la raiz del repo):
#   Rscript documentacion/figuras/generar_figuras.R
#
# Requiere ggplot2, dplyr, ggrepel, gridExtra (ademas de las dependencias del
# paquete).

suppressPackageStartupMessages({
  devtools::load_all(".", quiet = TRUE)
  library(ggplot2)
  library(dplyr)
})

outdir <- "documentacion/figuras"

tema <- theme_minimal(base_size = 12) +
  theme(
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold", size = 13),
    plot.subtitle = element_text(color = "grey30", size = 10.5),
    legend.position = "bottom"
  )

col_prim <- "#1b6ca8"
col_sec  <- "#c0392b"
col_ter  <- "#27884b"
col_gris <- "#7f8c8d"

# --- Correr el escenario de referencia completo (Pasos 1-5) -----------------

clima <- leer_clima_csv(system.file("extdata", "clima_ejemplo.csv", package = "balancehidrico"))
parametros <- leer_parametros_yaml(system.file("extdata", "parametros_ejemplo.yml", package = "balancehidrico"))
constantes <- leer_constantes_yaml()

fenologia <- calcular_fenologia("trigo", "intermedio-largo", clima, "1983-05-30", parametros)
p_cultivar <- obtener_parametros_cultivo(parametros, "trigo", "intermedio-largo")
prof_max <- obtener_profundidad_maxima_suelo(parametros, "IN64MARC02")

raices <- calcular_profundidad_radicular(
  clima_estacion = clima, fecha_emergencia = fenologia$hitos$emergencia,
  fecha_hito2 = fenologia$hitos$hito2, tb_c = p_cultivar$raiz$tb_c,
  pr_s_e = p_cultivar$raiz$pr_s_e, pr = p_cultivar$raiz$pr,
  profundidad_maxima_suelo = prof_max
)
kcb <- calcular_curva_kcb(fenologia$serie_diaria, p_cultivar$ut_e_fkcbini, p_cultivar$ut_e_ikcbmax,
                          p_cultivar$kcb$kcb_ini, p_cultivar$kcb$kcb_max)

suelo <- obtener_suelo_balance_hidrico(parametros, "IN64MARC02")
balance <- calcular_balance_hidrico(
  clima_estacion = clima, fecha_inicio = "1983-03-01",
  serie_profundidad_radicular = raices, serie_kcb = kcb, suelo = suelo,
  rastrojo_clase = "Moderada", humedad_inicial_clase_m1 = "Hu",
  humedad_inicial_clase_m2 = "Hu", constantes = constantes
)

hitos <- fenologia$hitos

# =============================================================================
# Figura 1 -- Fenologia (hitos) + curva de Kcb del escenario de referencia
# =============================================================================

serie_kcb_plot <- kcb %>% filter(date <= hitos$madurez_fisiologica + 10)

hitos_df <- tibble::tibble(
  fecha = c(hitos$siembra, hitos$emergencia, hitos$fin_kcb_inicial, hitos$inicio_kcb_maximo,
            hitos$hito1, hitos$inicio_periodo_critico, hitos$hito2, hitos$fin_periodo_critico,
            hitos$madurez_fisiologica),
  etiqueta = c("Siembra", "Emergencia", "Fin Kcb\ninicial", "Inicio Kcb\nmaximo",
               "ET", "Inicio\nperiodo critico", "Z71", "Fin\nperiodo critico", "Madurez\nfisiologica"),
  y = c(0.05, 0.15, 0.15, 1.10, 1.10, 1.10, 1.10, 1.10, 1.10)
)

periodo_critico <- tibble::tibble(xmin = hitos$inicio_periodo_critico, xmax = hitos$fin_periodo_critico)

fig1 <- ggplot() +
  geom_rect(data = periodo_critico, aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
            fill = col_sec, alpha = 0.10) +
  geom_line(data = serie_kcb_plot, aes(x = date, y = kcb), color = col_prim, linewidth = 1) +
  geom_vline(data = hitos_df, aes(xintercept = fecha), linetype = "dashed", color = col_gris, linewidth = 0.3) +
  geom_point(data = hitos_df[c(2, 5, 7), ], aes(x = fecha, y = 0), color = col_sec, size = 2.2) +
  annotate("text", x = hitos$inicio_periodo_critico + as.numeric(hitos$fin_periodo_critico - hitos$inicio_periodo_critico) / 2,
           y = 1.22, label = "Periodo critico", color = col_sec, size = 3.4, fontface = "italic") +
  ggrepel::geom_text_repel(data = hitos_df, aes(x = fecha, y = y, label = etiqueta),
                            size = 2.7, color = "grey25", segment.color = "grey70",
                            segment.size = 0.3, min.segment.length = 0,
                            box.padding = 0.5, max.overlaps = Inf, seed = 42) +
  scale_x_date(date_labels = "%b\n%Y", date_breaks = "1 month") +
  labs(
    title = "Fenologia y curva de Kcb -- escenario de referencia",
    subtitle = "Trigo, cultivar intermedio-largo, estacion 87480, siembra 1983-05-30",
    x = NULL, y = "Kcb"
  ) +
  tema

ggsave(file.path(outdir, "fig1_fenologia_kcb.png"), fig1, width = 8.5, height = 4.6, dpi = 300)
cat("fig1 OK\n")

# =============================================================================
# Figura 2 -- Balance hidrico diario: agua util (%) por metro y precipitacion,
# con la ventana de periodo critico resaltada
# =============================================================================

rango_fin <- hitos$fin_periodo_critico + 20

serie_bal <- balance$serie_diaria %>%
  left_join(dplyr::select(clima, date, pp), by = "date") %>%
  filter(date <= rango_fin)

fig2_top <- ggplot(serie_bal, aes(x = date)) +
  geom_rect(data = periodo_critico, aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
            inherit.aes = FALSE, fill = col_sec, alpha = 0.10) +
  geom_hline(yintercept = 30, linetype = "dotted", color = col_gris, linewidth = 0.4) +
  geom_line(aes(y = au_pct_m1 * 100, color = "0-1 m"), linewidth = 0.7) +
  geom_line(aes(y = au_pct_m2 * 100, color = "1-2 m"), linewidth = 0.7) +
  geom_line(aes(y = au_pct_total * 100, color = "Perfil 0-2.1 m"), linewidth = 0.9) +
  geom_vline(xintercept = hitos$siembra, linetype = "dashed", color = "grey40", linewidth = 0.4) +
  annotate("text", x = hitos$siembra, y = 5, label = "Siembra", size = 2.9, color = "grey30",
           angle = 90, vjust = -0.5, hjust = 0) +
  scale_color_manual(values = c("0-1 m" = col_prim, "1-2 m" = col_ter, "Perfil 0-2.1 m" = "grey20"), name = NULL) +
  scale_x_date(date_labels = "%b %Y", date_breaks = "1 month") +
  scale_y_continuous(limits = c(0, 100)) +
  labs(y = "Agua util (%)", x = NULL,
       title = "Balance hidrico diario -- escenario de referencia",
       subtitle = "Desde el 1 de marzo hasta el fin del periodo critico (+20 dias); linea punteada = umbral de sandwich seco (30%)") +
  tema +
  theme(legend.position = "top")

fig2_bottom <- ggplot(serie_bal, aes(x = date, y = pp)) +
  geom_col(fill = col_prim, width = 1) +
  scale_x_date(date_labels = "%b %Y", date_breaks = "1 month") +
  labs(y = "Pp (mm/dia)", x = NULL) +
  tema +
  theme(plot.margin = margin(t = 2))

fig2 <- gridExtra::arrangeGrob(fig2_top, fig2_bottom, heights = c(3, 1))
ggsave(file.path(outdir, "fig2_balance_hidrico.png"), fig2, width = 8.5, height = 6, dpi = 300)
cat("fig2 OK\n")

# =============================================================================
# Figura 3 -- Fotoperiodo: formula sin correccion de crepusculo vs con
# correccion de crepusculo civil, para la latitud de la estacion de referencia
# =============================================================================

lat <- obtener_latitud_estacion(parametros, "87480")

fp_sin_crepusculo <- function(doy, lat) {
  decl <- 23.45 * sin((360 / 365 * (doy - 81)) * pi / 180)
  x <- -tan(lat * pi / 180) * tan(decl * pi / 180)
  x <- pmin(pmax(x, -1), 1)
  24 / pi * acos(x)
}

doy <- 1:365
df_fp <- tibble::tibble(
  doy = doy,
  fecha = as.Date("1983-01-01") + doy - 1,
  sin_crepusculo = fp_sin_crepusculo(doy, lat),
  con_crepusculo = calcular_fotoperiodo(doy, lat)
)

fig3 <- ggplot(df_fp, aes(x = fecha)) +
  geom_line(aes(y = sin_crepusculo, color = "Sin correccion (formula original)"), linewidth = 0.9) +
  geom_line(aes(y = con_crepusculo, color = "Con crepusculo civil (formula vigente)"), linewidth = 0.9) +
  scale_color_manual(values = c("Sin correccion (formula original)" = col_gris,
                                 "Con crepusculo civil (formula vigente)" = col_sec), name = NULL) +
  scale_x_date(date_labels = "%b", date_breaks = "1 month") +
  labs(
    title = "Fotoperiodo estimado segun submodelo de duracion del dia",
    subtitle = paste0("Estacion 87480 (lat ", round(lat, 2), "S) -- la correccion agrega ~0.5 h en cualquier epoca del anio"),
    x = NULL, y = "Fotoperiodo (h)"
  ) +
  tema +
  theme(legend.position = "top")

ggsave(file.path(outdir, "fig3_fotoperiodo.png"), fig3, width = 8, height = 4.2, dpi = 300)
cat("fig3 OK\n")

cat("Listo. Figuras en", outdir, "\n")
