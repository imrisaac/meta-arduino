/*
 * Arduino UNO Q dash prototype: speedometer, tachometer, gear and fuel drawn
 * with LVGL straight to DRM/KMS, without a compositor.
 *
 * READY is sent to systemd once the first frame is on screen, so
 * arduino-app.target marks the first frame. If no display shows up within
 * DISPLAY_WAIT_MS, READY is sent anyway so the rest of the boot can go on,
 * and the dash starts whenever a display is connected.
 *
 * Values are simulated for now.
 */

#include <fcntl.h>
#include <glob.h>
#include <math.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>

#include <systemd/sd-daemon.h>
#include <xf86drmMode.h>

#include "lvgl/lvgl.h"

#define DISPLAY_WAIT_MS 5000
#define SWEEP_MS        1200
#define SPEED_MAX       240
#define RPM_MAX         8000
#define RPM_REDLINE     6500

struct gauge {
	lv_obj_t *scale;
	lv_obj_t *needle;
	lv_obj_t *value;
	int32_t needle_len;
};

static struct gauge speedo, tacho;
static lv_obj_t *gear_label;
static lv_obj_t *fuel_bar;
static lv_style_t redline_style;
static uint32_t start_ms;

static const char *rpm_labels[] = {"0", "1", "2", "3", "4", "5", "6", "7", "8", NULL};

static uint32_t tick_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/*
 * With msm.separate_gpu_kms=1 the GPU is a card of its own, and opening it
 * starts the GPU and its zap-shader load. Only cards with connectors in sysfs
 * can drive a display, so skip the rest without opening them.
 */
static int card_has_connectors(int card)
{
	char pattern[64];
	glob_t g;
	int ret;

	snprintf(pattern, sizeof(pattern), "/sys/class/drm/card%d-*", card);
	ret = glob(pattern, 0, NULL, &g) == 0 && g.gl_pathc > 0;
	globfree(&g);
	return ret;
}

/* Return the first DRM card with a connected output, waiting for it up to timeout_ms */
static int find_card(char *path, size_t len, uint32_t timeout_ms)
{
	uint32_t start = tick_ms();

	do {
		for (int i = 0; i < 4; i++) {
			int found = 0;
			int fd;

			if (!card_has_connectors(i))
				continue;

			snprintf(path, len, "/dev/dri/card%d", i);
			fd = open(path, O_RDWR | O_CLOEXEC);
			if (fd < 0)
				continue;

			drmModeRes *res = drmModeGetResources(fd);
			for (int c = 0; res && c < res->count_connectors && !found; c++) {
				drmModeConnector *conn = drmModeGetConnector(fd, res->connectors[c]);
				found = conn && conn->connection == DRM_MODE_CONNECTED && conn->count_modes > 0;
				drmModeFreeConnector(conn);
			}
			drmModeFreeResources(res);
			close(fd);

			if (found)
				return 0;
		}
		usleep(20 * 1000);
	} while (tick_ms() - start < timeout_ms);

	return -1;
}

static void gauge_create(struct gauge *g, lv_obj_t *parent, int32_t size, int32_t max,
			 uint32_t ticks, uint32_t major_every, int32_t redline,
			 const char *text_src[], const char *unit)
{
	lv_obj_t *unit_label;

	g->scale = lv_scale_create(parent);
	lv_obj_set_size(g->scale, size, size);
	lv_scale_set_mode(g->scale, LV_SCALE_MODE_ROUND_INNER);
	lv_scale_set_range(g->scale, 0, max);
	lv_scale_set_total_tick_count(g->scale, ticks);
	lv_scale_set_major_tick_every(g->scale, major_every);
	lv_scale_set_label_show(g->scale, true);
	lv_scale_set_angle_range(g->scale, 270);
	lv_scale_set_rotation(g->scale, 135);
	if (text_src)
		lv_scale_set_text_src(g->scale, text_src);

	lv_obj_set_style_bg_opa(g->scale, LV_OPA_COVER, 0);
	lv_obj_set_style_bg_color(g->scale, lv_color_hex(0x101418), 0);
	lv_obj_set_style_radius(g->scale, LV_RADIUS_CIRCLE, 0);
	lv_obj_set_style_pad_all(g->scale, size / 20, 0);
	lv_obj_set_style_arc_color(g->scale, lv_color_hex(0x40464c), LV_PART_MAIN);
	lv_obj_set_style_line_color(g->scale, lv_color_hex(0xa0a8b0), LV_PART_ITEMS);
	lv_obj_set_style_line_color(g->scale, lv_color_white(), LV_PART_INDICATOR);
	lv_obj_set_style_length(g->scale, size / 40, LV_PART_ITEMS);
	lv_obj_set_style_length(g->scale, size / 18, LV_PART_INDICATOR);
	lv_obj_set_style_line_width(g->scale, 3, LV_PART_INDICATOR);
	lv_obj_set_style_text_color(g->scale, lv_color_white(), LV_PART_INDICATOR);
	lv_obj_set_style_text_font(g->scale, &lv_font_montserrat_24, LV_PART_INDICATOR);

	if (redline < max) {
		lv_scale_section_t *section = lv_scale_add_section(g->scale);
		lv_scale_set_section_range(g->scale, section, redline, max);
		lv_scale_set_section_style_indicator(g->scale, section, &redline_style);
		lv_scale_set_section_style_items(g->scale, section, &redline_style);
	}

	g->needle_len = size / 2 - size / 7;
	g->needle = lv_line_create(g->scale);
	lv_obj_set_style_line_width(g->needle, 6, 0);
	lv_obj_set_style_line_rounded(g->needle, true, 0);
	lv_obj_set_style_line_color(g->needle, lv_palette_main(LV_PALETTE_ORANGE), 0);

	g->value = lv_label_create(g->scale);
	lv_obj_set_style_text_font(g->value, &lv_font_montserrat_48, 0);
	lv_obj_set_style_text_color(g->value, lv_color_white(), 0);
	lv_obj_align(g->value, LV_ALIGN_CENTER, 0, size / 5);

	unit_label = lv_label_create(g->scale);
	lv_label_set_text(unit_label, unit);
	lv_obj_set_style_text_font(unit_label, &lv_font_montserrat_24, 0);
	lv_obj_set_style_text_color(unit_label, lv_color_hex(0xa0a8b0), 0);
	lv_obj_align(unit_label, LV_ALIGN_CENTER, 0, size / 5 + 44);
}

static void gauge_set(struct gauge *g, int32_t needle, int32_t shown)
{
	lv_scale_set_line_needle_value(g->scale, g->needle, g->needle_len, needle);
	lv_label_set_text_fmt(g->value, "%d", (int)shown);
}

static void dash_create(lv_display_t *disp)
{
	int32_t w = lv_display_get_horizontal_resolution(disp);
	int32_t h = lv_display_get_vertical_resolution(disp);
	int32_t size = LV_MIN(h * 85 / 100, w * 42 / 100);
	lv_obj_t *screen = lv_screen_active();
	lv_obj_t *label;

	lv_style_init(&redline_style);
	lv_style_set_line_color(&redline_style, lv_palette_main(LV_PALETTE_RED));
	lv_style_set_text_color(&redline_style, lv_palette_main(LV_PALETTE_RED));

	lv_obj_set_style_bg_color(screen, lv_color_black(), 0);
	lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE);

	gauge_create(&speedo, screen, size, SPEED_MAX, 25, 2, SPEED_MAX, NULL, "km/h");
	lv_obj_align(speedo.scale, LV_ALIGN_LEFT_MID, w / 30, 0);

	gauge_create(&tacho, screen, size, RPM_MAX, 41, 5, RPM_REDLINE, rpm_labels, "x1000 rpm");
	lv_obj_align(tacho.scale, LV_ALIGN_RIGHT_MID, -w / 30, 0);

	gear_label = lv_label_create(screen);
	lv_obj_set_style_text_font(gear_label, &lv_font_montserrat_48, 0);
	lv_obj_set_style_text_color(gear_label, lv_palette_main(LV_PALETTE_ORANGE), 0);
	lv_obj_align(gear_label, LV_ALIGN_CENTER, 0, -h / 10);

	label = lv_label_create(screen);
	lv_label_set_text(label, "FUEL");
	lv_obj_set_style_text_font(label, &lv_font_montserrat_24, 0);
	lv_obj_set_style_text_color(label, lv_color_hex(0xa0a8b0), 0);
	lv_obj_align(label, LV_ALIGN_CENTER, 0, h / 8);

	fuel_bar = lv_bar_create(screen);
	lv_obj_set_size(fuel_bar, w / 8, h / 40 + 4);
	lv_bar_set_range(fuel_bar, 0, 100);
	lv_obj_set_style_bg_color(fuel_bar, lv_color_hex(0x40464c), LV_PART_MAIN);
	lv_obj_set_style_bg_color(fuel_bar, lv_palette_main(LV_PALETTE_GREEN), LV_PART_INDICATOR);
	lv_obj_align_to(fuel_bar, label, LV_ALIGN_OUT_BOTTOM_MID, 0, 8);
}

/* Startup needle sweep, then a simulated drive through the gears */
static void dash_update(lv_timer_t *timer)
{
	static const int32_t gear_top[] = {0, 20, 45, 75, 110, 150, SPEED_MAX};
	uint32_t t = tick_ms() - start_ms;
	int32_t speed, rpm, gear = 1;

	LV_UNUSED(timer);

	if (t < SWEEP_MS) {
		float k = sinf((float)M_PI * t / SWEEP_MS);
		gauge_set(&speedo, (int32_t)(k * SPEED_MAX), 0);
		gauge_set(&tacho, (int32_t)(k * RPM_MAX), 0);
		lv_label_set_text(gear_label, "P");
		lv_bar_set_value(fuel_bar, (int32_t)(k * 100), LV_ANIM_OFF);
		return;
	}

	t -= SWEEP_MS;
	speed = (int32_t)(70 - 60 * cosf(t / 6000.0f));
	while (gear < 6 && speed > gear_top[gear])
		gear++;
	rpm = 900 + (speed - gear_top[gear - 1]) * 5600 / (gear_top[gear] - gear_top[gear - 1]);

	gauge_set(&speedo, speed, speed);
	gauge_set(&tacho, rpm, rpm / 100 * 100);
	lv_label_set_text_fmt(gear_label, "%d", (int)gear);
	lv_bar_set_value(fuel_bar, 100 - (int32_t)(t / 6000 % 100), LV_ANIM_OFF);
}

int main(void)
{
	char card[32];
	lv_display_t *disp;

	if (find_card(card, sizeof(card), DISPLAY_WAIT_MS) < 0) {
		fprintf(stderr, "no display after %d ms, waiting for one\n", DISPLAY_WAIT_MS);
		sd_notify(0, "READY=1\nSTATUS=Waiting for a display");
		while (find_card(card, sizeof(card), DISPLAY_WAIT_MS) < 0)
			;
	}

	lv_init();
	lv_tick_set_cb(tick_ms);

	disp = lv_linux_drm_create();
	if (lv_linux_drm_set_file(disp, card, -1) != LV_RESULT_OK) {
		fprintf(stderr, "cannot drive %s\n", card);
		return 1;
	}

	dash_create(disp);
	start_ms = tick_ms();
	dash_update(NULL);
	lv_refr_now(disp);

	fprintf(stderr, "first frame on %s at %u ms after kernel start\n", card, tick_ms());
	sd_notify(0, "READY=1\nSTATUS=Running");

	lv_timer_create(dash_update, 16, NULL);
	while (1)
		usleep(LV_MIN(lv_timer_handler(), 50) * 1000);
}
