/*
 * Boot indicator for the Arduino UNO Q LED matrix.
 *
 * The Zephyr loader plays the stock boot animation until arduino-router is up
 * on Linux, and only then starts this sketch: the sketch starting marks
 * arduino-app.target. Linux calls boot_done(app_ms, full_ms) once systemd
 * reports the whole boot finished; both times are counted from power-on.
 */

#include <Arduino_RouterBridge.h>
#include "ArduinoGraphics.h"
#include "Arduino_LED_Matrix.h"

Arduino_LED_Matrix matrix;

// Written from the Bridge thread, read from loop()
static volatile bool booted = false;
static volatile int app_ms = 0;
static volatile int full_ms = 0;

static uint8_t frame[8][13];

static uint8_t check[8][13] = {
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0},
	{0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0},
	{0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
};

bool boot_done(int app, int full) {
	app_ms = app;
	full_ms = full;
	booted = true;
	return true;
}

static String seconds(int ms) {
	return String(ms / 1000) + "." + String((ms % 1000) / 100) + "s";
}

// The app is up, the rest of the system is still starting: 0 to 3 dots
static void drawProgress(int lit) {
	memset(frame, 0, sizeof(frame));
	for (int d = 0; d < lit; d++) {
		for (int y = 3; y <= 4; y++) {
			frame[y][1 + d * 4] = 1;
			frame[y][2 + d * 4] = 1;
		}
	}
	matrix.renderBitmap(frame, 8, 13);
}

void setup() {
	matrix.begin();
	matrix.textFont(Font_5x7);
	matrix.textScrollSpeed(60);
	drawProgress(1);

	Bridge.begin();
	Bridge.provide("boot_done", boot_done);
}

void loop() {
	static int step = 0;

	if (!booted) {
		drawProgress(step);
		step = (step + 1) % 4;
		delay(250);
		return;
	}

	matrix.renderBitmap(check, 8, 13);
	delay(2000);

	String text = String(" ") + seconds(app_ms) + " / " + seconds(full_ms) + " ";
	matrix.beginText(0, 1, 127, 0, 0);
	matrix.print(text);
	matrix.endText(SCROLL_LEFT);
}
