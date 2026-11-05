/*
 * Arduino UNO Q instrument cluster prototype: QML rendered on the GPU with
 * OpenGL ES through eglfs/KMS, without a compositor.
 *
 * Built to measure how long Qt Quick takes to its first frame. Once it is
 * handed to the display, one line is logged with the time each startup
 * stage ended, in ms since the kernel started (CLOCK_MONOTONIC):
 *   exec     the process was started
 *   main     main() was entered: Qt and its dependencies are linked in
 *   display  a DRM card with a connected display showed up
 *   gui      QGuiApplication is up: eglfs, EGL/GBM and DRM/KMS initialised
 *   qml      the QML is loaded and the window created
 *   frame    the first frame was queued for display (at most one refresh
 *            before it is on screen); READY=1 is sent to systemd
 * and the OpenGL renderer, to tell the GPU (FD702) from a software fallback.
 *
 * As in arduino-dash, if no display shows up within DISPLAY_WAIT_MS, READY
 * is sent anyway so the rest of the boot can go on.
 *
 * Development aids: ARDUINO_CLUSTER_CAMERA=<n> shows camera n from startup,
 * and SIGUSR1 (systemctl kill -s USR1 arduino-cluster) saves what is on
 * screen to $RUNTIME_DIRECTORY/screenshot.png.
 */

#include <QGuiApplication>
#include <QImage>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QSocketNotifier>

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>

#include <csignal>

#include <fcntl.h>
#include <glob.h>
#include <sys/signalfd.h>
#include <unistd.h>

#include <systemd/sd-daemon.h>
#include <xf86drmMode.h>

#define DISPLAY_WAIT_MS 5000

static double now_ms()
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}

/* When the process was started: field 22 of /proc/self/stat, in clock ticks */
static double exec_ms()
{
	unsigned long long start;
	char buf[1024];
	size_t len = 0;
	FILE *f;
	char *p;

	f = fopen("/proc/self/stat", "r");
	if (f) {
		len = fread(buf, 1, sizeof(buf) - 1, f);
		fclose(f);
	}
	buf[len] = '\0';

	/* The command name may contain spaces; field 3 follows its ')' */
	p = strrchr(buf, ')');
	if (!p || sscanf(p + 1, " %*c %*d %*d %*d %*d %*d %*u %*u %*u %*u %*u %*u %*u"
			 " %*d %*d %*d %*d %*d %*d %llu", &start) != 1)
		return -1;
	return start * 1e3 / sysconf(_SC_CLK_TCK);
}

/*
 * Only cards with connectors in sysfs can drive a display; with
 * msm.separate_gpu_kms=1 the GPU would be a card of its own.
 */
static bool card_has_connectors(int card)
{
	char pattern[64];
	glob_t g;
	bool ret;

	snprintf(pattern, sizeof(pattern), "/sys/class/drm/card%d-*", card);
	ret = glob(pattern, 0, NULL, &g) == 0 && g.gl_pathc > 0;
	globfree(&g);
	return ret;
}

static bool card_connected(const char *path)
{
	bool found = false;
	drmModeRes *res;
	int fd;

	fd = open(path, O_RDWR | O_CLOEXEC);
	if (fd < 0)
		return false;

	/* GETCONNECTOR probes the connector, unlike the status file in sysfs */
	res = drmModeGetResources(fd);
	for (int c = 0; res && c < res->count_connectors && !found; c++) {
		drmModeConnector *conn = drmModeGetConnector(fd, res->connectors[c]);

		found = conn && conn->connection == DRM_MODE_CONNECTED && conn->count_modes > 0;
		drmModeFreeConnector(conn);
	}
	drmModeFreeResources(res);
	close(fd);
	return found;
}

/* Return the first DRM card with a connected output, waiting for it up to timeout_ms */
static bool find_card(char *path, size_t len, double timeout_ms)
{
	double start = now_ms();

	do {
		for (int i = 0; i < 4; i++) {
			if (!card_has_connectors(i))
				continue;
			snprintf(path, len, "/dev/dri/card%d", i);
			if (card_connected(path))
				return true;
		}
		usleep(20 * 1000);
	} while (now_ms() - start < timeout_ms);

	return false;
}

static const char *runtime_dir()
{
	const char *dir = getenv("RUNTIME_DIRECTORY");

	return dir ? dir : "/tmp";
}

/* Point eglfs at the card found, instead of letting it pick one */
static void write_kms_config(const char *card)
{
	char path[256];
	FILE *f;

	snprintf(path, sizeof(path), "%s/kms.json", runtime_dir());
	f = fopen(path, "w");
	if (!f) {
		perror(path);
		return;
	}
	fprintf(f, "{ \"device\": \"%s\", \"hwcursor\": false }\n", card);
	fclose(f);
	setenv("QT_QPA_EGLFS_KMS_CONFIG", path, 0);
}

int main(int argc, char *argv[])
{
	const double t_exec = exec_ms();
	const double t_main = now_ms();
	static std::atomic_flag first_render = ATOMIC_FLAG_INIT;
	static std::atomic_flag first_frame = ATOMIC_FLAG_INIT;
	static char renderer[128] = "?";
	char card[32];
	sigset_t usr1;

	/* Before any thread starts, so that only the signalfd below sees SIGUSR1 */
	sigemptyset(&usr1);
	sigaddset(&usr1, SIGUSR1);
	pthread_sigmask(SIG_BLOCK, &usr1, nullptr);

	if (!find_card(card, sizeof(card), DISPLAY_WAIT_MS)) {
		fprintf(stderr, "no display after %d ms, waiting for one\n", DISPLAY_WAIT_MS);
		sd_notify(0, "READY=1\nSTATUS=Waiting for a display");
		while (!find_card(card, sizeof(card), DISPLAY_WAIT_MS))
			;
	}
	const double t_display = now_ms();
	write_kms_config(card);

	QGuiApplication app(argc, argv);
	const double t_gui = now_ms();

	QQmlApplicationEngine engine;
	if (qEnvironmentVariableIsSet("ARDUINO_CLUSTER_CAMERA"))
		engine.setInitialProperties({{ "camera", qEnvironmentVariableIntValue("ARDUINO_CLUSTER_CAMERA") }});
	engine.loadFromModule("Cluster", "Main");
	QQuickWindow *window = engine.rootObjects().isEmpty() ? nullptr :
		qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
	if (!window) {
		fprintf(stderr, "cannot create the cluster window\n");
		return 1;
	}
	const double t_qml = now_ms();

	/* Both emitted on the render thread; the OpenGL context is current in the first */
	QObject::connect(window, &QQuickWindow::beforeRendering, window, [] {
		QOpenGLContext *ctx = QOpenGLContext::currentContext();
		const GLubyte *name;

		if (first_render.test_and_set() || !ctx)
			return;
		name = ctx->functions()->glGetString(GL_RENDERER);
		if (name)
			snprintf(renderer, sizeof(renderer), "%s", (const char *)name);
	}, Qt::DirectConnection);

	QObject::connect(window, &QQuickWindow::frameSwapped, window, [=] {
		if (first_frame.test_and_set())
			return;

		fprintf(stderr, "first frame on %s at %.0f ms after kernel start "
			"(exec %.0f, main %.0f, display %.0f, gui %.0f, qml %.0f), GPU: %s\n",
			card, now_ms(), t_exec, t_main, t_display, t_gui, t_qml, renderer);
		sd_notify(0, "READY=1\nSTATUS=Running");
	}, Qt::DirectConnection);

	const int sfd = signalfd(-1, &usr1, SFD_NONBLOCK | SFD_CLOEXEC);
	QSocketNotifier screenshot(sfd, QSocketNotifier::Read);
	QObject::connect(&screenshot, &QSocketNotifier::activated, window, [=] {
		struct signalfd_siginfo si;
		char path[256];

		while (read(sfd, &si, sizeof(si)) == sizeof(si))
			;
		snprintf(path, sizeof(path), "%s/screenshot.png", runtime_dir());
		fprintf(stderr, "screenshot %s: %s\n", path, window->grabWindow().save(path) ? "saved" : "failed");
	});

	return app.exec();
}
