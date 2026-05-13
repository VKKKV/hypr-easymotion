#define _GNU_SOURCE
#include "shim.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <cairo/cairo.h>
#include <pango/pangocairo.h>

const struct wl_interface xdg_popup_interface = { "xdg_popup", 1, 0, NULL, 0, NULL };

static uint32_t min_u32(uint32_t a, uint32_t b) { return a < b ? a : b; }

struct wl_compositor *em_bind_compositor(struct wl_registry *registry, uint32_t name, uint32_t version) {
    return wl_registry_bind(registry, name, &wl_compositor_interface, min_u32(version, 6));
}

struct wl_shm *em_bind_shm(struct wl_registry *registry, uint32_t name, uint32_t version) {
    return wl_registry_bind(registry, name, &wl_shm_interface, min_u32(version, 1));
}

struct wl_seat *em_bind_seat(struct wl_registry *registry, uint32_t name, uint32_t version) {
    return wl_registry_bind(registry, name, &wl_seat_interface, min_u32(version, 9));
}

struct wl_output *em_bind_output(struct wl_registry *registry, uint32_t name, uint32_t version) {
    return wl_registry_bind(registry, name, &wl_output_interface, min_u32(version, 4));
}

struct zwlr_layer_shell_v1 *em_bind_layer_shell(struct wl_registry *registry, uint32_t name, uint32_t version) {
    return wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, min_u32(version, 5));
}

struct wl_surface *em_compositor_create_surface(struct wl_compositor *compositor) {
    return wl_compositor_create_surface(compositor);
}

struct zwlr_layer_surface_v1 *em_layer_shell_get_layer_surface(struct zwlr_layer_shell_v1 *shell, struct wl_surface *surface, struct wl_output *output) {
    return zwlr_layer_shell_v1_get_layer_surface(shell, surface, output, ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, "easymotion");
}

void em_layer_surface_set_fullscreen(struct zwlr_layer_surface_v1 *surface) {
    zwlr_layer_surface_v1_set_size(surface, 0, 0);
    zwlr_layer_surface_v1_set_anchor(surface,
        ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
    zwlr_layer_surface_v1_set_exclusive_zone(surface, -1);
    zwlr_layer_surface_v1_set_keyboard_interactivity(surface, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE);
}

void em_layer_surface_ack_configure(struct zwlr_layer_surface_v1 *surface, uint32_t serial) {
    zwlr_layer_surface_v1_ack_configure(surface, serial);
}

struct wl_keyboard *em_seat_get_keyboard(struct wl_seat *seat) {
    return wl_seat_get_keyboard(seat);
}

struct wl_shm_pool *em_shm_create_pool(struct wl_shm *shm, int fd, int32_t size) {
    return wl_shm_create_pool(shm, fd, size);
}

struct wl_buffer *em_shm_pool_create_argb8888_buffer(struct wl_shm_pool *pool, int32_t width, int32_t height, int32_t stride) {
    return wl_shm_pool_create_buffer(pool, 0, width, height, stride, WL_SHM_FORMAT_ARGB8888);
}

void em_surface_attach_damage_commit(struct wl_surface *surface, struct wl_buffer *buffer, int32_t width, int32_t height) {
    wl_surface_attach(surface, buffer, 0, 0);
    wl_surface_damage_buffer(surface, 0, 0, width, height);
    wl_surface_commit(surface);
}

int em_create_shm_file(int32_t size) {
    int fd = memfd_create("hypr-easymotion", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (fd < 0) {
        struct timespec ts = { 0, 0 };
        clock_gettime(CLOCK_MONOTONIC, &ts);
        for (unsigned int attempt = 0; attempt < 100; attempt++) {
            char name[64];
            snprintf(name, sizeof(name), "/hypr-easymotion-%ld-%ld-%u", (long)getpid(), (long)ts.tv_nsec, attempt);
            fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0600);
            if (fd >= 0) {
                shm_unlink(name);
                break;
            }
            if (errno != EEXIST) break;
        }
    }
    if (fd < 0) return -1;
    if (ftruncate(fd, size) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static void set_source(cairo_t *cr, const double color[4]) {
    cairo_set_source_rgba(cr, color[0], color[1], color[2], color[3]);
}

static void rounded_rect(cairo_t *cr, double x, double y, double w, double h, double r) {
    double radius = r;
    double max_radius = (w < h ? w : h) / 2.0;
    if (radius > max_radius) radius = max_radius;
    if (radius <= 0.0) {
        cairo_rectangle(cr, x, y, w, h);
        return;
    }
    cairo_new_sub_path(cr);
    cairo_arc(cr, x + w - radius, y + radius, radius, -G_PI / 2.0, 0.0);
    cairo_arc(cr, x + w - radius, y + h - radius, radius, 0.0, G_PI / 2.0);
    cairo_arc(cr, x + radius, y + h - radius, radius, G_PI / 2.0, G_PI);
    cairo_arc(cr, x + radius, y + radius, radius, G_PI, 3.0 * G_PI / 2.0);
    cairo_close_path(cr);
}

int em_render_labels(unsigned char *data, int32_t width, int32_t height, int32_t stride, const struct em_style *style, const struct em_label *labels, uint32_t label_count) {
    cairo_surface_t *surface = cairo_image_surface_create_for_data(data, CAIRO_FORMAT_ARGB32, width, height, stride);
    if (!surface || cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) return -1;
    cairo_t *cr = cairo_create(surface);
    if (!cr || cairo_status(cr) != CAIRO_STATUS_SUCCESS) {
        cairo_surface_destroy(surface);
        return -1;
    }

    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR);
    cairo_paint(cr);
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

    for (uint32_t i = 0; i < label_count; i++) {
        PangoLayout *layout = pango_cairo_create_layout(cr);
        PangoFontDescription *font = pango_font_description_new();
        if (!layout || !font) {
            if (font) pango_font_description_free(font);
            if (layout) g_object_unref(layout);
            cairo_destroy(cr);
            cairo_surface_destroy(surface);
            return -1;
        }
        pango_font_description_set_family(font, style->textfont);
        pango_font_description_set_absolute_size(font, style->textsize * PANGO_SCALE);
        pango_layout_set_font_description(layout, font);
        pango_layout_set_text(layout, labels[i].text, -1);

        int text_w = 0;
        int text_h = 0;
        pango_layout_get_pixel_size(layout, &text_w, &text_h);
        double rect_w = text_w + style->textpadding * 2.0;
        double rect_h = text_h + style->textpadding * 2.0;
        double rect_x = labels[i].x + labels[i].w / 2.0 - rect_w / 2.0;
        double rect_y = labels[i].y + labels[i].h / 2.0 - rect_h / 2.0;

        rounded_rect(cr, rect_x, rect_y, rect_w, rect_h, style->rounding);
        set_source(cr, style->bgcolor);
        cairo_fill_preserve(cr);
        if (style->bordersize > 0.0) {
            cairo_set_line_width(cr, style->bordersize);
            set_source(cr, style->bordercolor);
            cairo_stroke(cr);
        } else {
            cairo_new_path(cr);
        }
        cairo_move_to(cr, rect_x + style->textpadding, rect_y + style->textpadding);
        set_source(cr, style->textcolor);
        pango_cairo_show_layout(cr, layout);

        pango_font_description_free(font);
        g_object_unref(layout);
    }

    cairo_surface_flush(surface);
    cairo_destroy(cr);
    cairo_surface_destroy(surface);
    return 0;
}
