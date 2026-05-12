#pragma once

#include <stdint.h>
#include <wayland-client.h>
#include "wlr-layer-shell-unstable-v1-client-protocol.h"

struct wl_compositor *em_bind_compositor(struct wl_registry *registry, uint32_t name, uint32_t version);
struct wl_shm *em_bind_shm(struct wl_registry *registry, uint32_t name, uint32_t version);
struct wl_seat *em_bind_seat(struct wl_registry *registry, uint32_t name, uint32_t version);
struct wl_output *em_bind_output(struct wl_registry *registry, uint32_t name, uint32_t version);
struct zwlr_layer_shell_v1 *em_bind_layer_shell(struct wl_registry *registry, uint32_t name, uint32_t version);

struct wl_surface *em_compositor_create_surface(struct wl_compositor *compositor);
struct zwlr_layer_surface_v1 *em_layer_shell_get_layer_surface(struct zwlr_layer_shell_v1 *shell, struct wl_surface *surface, struct wl_output *output);
void em_layer_surface_set_fullscreen(struct zwlr_layer_surface_v1 *surface);
void em_layer_surface_ack_configure(struct zwlr_layer_surface_v1 *surface, uint32_t serial);

struct wl_keyboard *em_seat_get_keyboard(struct wl_seat *seat);
struct wl_shm_pool *em_shm_create_pool(struct wl_shm *shm, int fd, int32_t size);
struct wl_buffer *em_shm_pool_create_argb8888_buffer(struct wl_shm_pool *pool, int32_t width, int32_t height, int32_t stride);
void em_surface_attach_damage_commit(struct wl_surface *surface, struct wl_buffer *buffer, int32_t width, int32_t height);
int em_create_shm_file(int32_t size);

struct em_style {
    double textsize;
    double textcolor[4];
    double bgcolor[4];
    const char *textfont;
    double textpadding;
    double rounding;
    double bordersize;
    double bordercolor[4];
};

struct em_label {
    const char *text;
    double x;
    double y;
    double w;
    double h;
};

int em_render_labels(unsigned char *data, int32_t width, int32_t height, int32_t stride, const struct em_style *style, const struct em_label *labels, uint32_t label_count);
