/* SDL2/Wayland platform shim only. Gameplay and renderer ownership stay in Rust.
 * Presentation feedback is actual compositor feedback, never inferred from swap calls.
 */
#include <SDL.h>
#include <SDL_syswm.h>
#include <wayland-client.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "presentation-time-client-protocol.h"

#define CAPACITY 512
struct egg_sample {
    uint64_t frame, tick, timestamp_ns, submitted_ns, sequence;
    uint32_t refresh_ns, flags, presented, reserved;
};
struct egg_stats {
    uint64_t requested, presented, discarded, pending, maximum_pending, lost_samples;
    uint32_t clock_id, available;
};
struct egg_present;
struct pending {
    struct pending *next;
    struct egg_present *owner;
    struct wp_presentation_feedback *feedback;
    uint64_t frame, tick, submitted_ns;
};
struct egg_present {
    struct wl_display *display;
    struct wl_surface *surface;
    struct wl_registry *registry;
    struct wp_presentation *presentation;
    uint32_t global_name;
    struct pending *head;
    struct egg_stats stats;
    struct egg_sample samples[CAPACITY];
    unsigned begin, length;
};
static uint64_t monotonic_ns(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t) != 0) return 0;
    return (uint64_t)t.tv_sec * UINT64_C(1000000000) + (uint64_t)t.tv_nsec;
}
static void clock_id(void *data, struct wp_presentation *object, uint32_t id) {
    (void)object;
    ((struct egg_present *)data)->stats.clock_id = id;
}
static const struct wp_presentation_listener presentation_listener = {clock_id};
static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
    struct egg_present *p = data;
    (void)version;
    if (!p->presentation && strcmp(interface, "wp_presentation") == 0) {
        p->presentation = wl_registry_bind(registry, name, &wp_presentation_interface, 1);
        p->global_name = name;
        p->stats.available = 1;
        wp_presentation_add_listener(p->presentation, &presentation_listener, p);
    }
}
static void removed(void *data, struct wl_registry *registry, uint32_t name) {
    struct egg_present *p = data;
    (void)registry;
    if (name == p->global_name) p->stats.available = 0;
}
static const struct wl_registry_listener registry_listener = {global, removed};
static void finish(struct pending *pending, struct egg_sample sample) {
    struct egg_present *p = pending->owner;
    sample.frame = pending->frame;
    sample.tick = pending->tick;
    sample.submitted_ns = pending->submitted_ns;
    if (p->length == CAPACITY) p->stats.lost_samples++;
    else {
        p->samples[(p->begin + p->length) % CAPACITY] = sample;
        p->length++;
    }
    struct pending **cursor = &p->head;
    while (*cursor && *cursor != pending) cursor = &(*cursor)->next;
    if (*cursor) *cursor = pending->next;
    p->stats.pending--;
    wp_presentation_feedback_destroy(pending->feedback);
    free(pending);
}
static void sync_output(void *data, struct wp_presentation_feedback *feedback,
                        struct wl_output *output) {
    (void)data; (void)feedback; (void)output;
}
static void presented(void *data, struct wp_presentation_feedback *feedback,
                      uint32_t sec_hi, uint32_t sec_lo, uint32_t nsec,
                      uint32_t refresh, uint32_t seq_hi, uint32_t seq_lo,
                      uint32_t flags) {
    (void)feedback;
    struct pending *pending = data;
    pending->owner->stats.presented++;
    uint64_t sec = ((uint64_t)sec_hi << 32) | sec_lo;
    struct egg_sample sample = {0};
    sample.timestamp_ns = sec * UINT64_C(1000000000) + nsec;
    sample.sequence = ((uint64_t)seq_hi << 32) | seq_lo;
    sample.refresh_ns = refresh;
    sample.flags = flags;
    sample.presented = 1;
    finish(pending, sample);
}
static void discarded(void *data, struct wp_presentation_feedback *feedback) {
    (void)feedback;
    struct pending *pending = data;
    pending->owner->stats.discarded++;
    struct egg_sample sample = {0};
    finish(pending, sample);
}
static const struct wp_presentation_feedback_listener feedback_listener = {
    sync_output, presented, discarded
};
void *egg_present_create(SDL_Window *window) {
    struct SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (!SDL_GetWindowWMInfo(window, &info) || info.subsystem != SDL_SYSWM_WAYLAND) {
        SDL_SetError("actual native Wayland window required for presentation feedback");
        return NULL;
    }
    struct egg_present *p = calloc(1, sizeof(*p));
    if (!p) { SDL_OutOfMemory(); return NULL; }
    p->display = info.info.wl.display;
    p->surface = info.info.wl.surface;
    p->registry = wl_display_get_registry(p->display);
    wl_registry_add_listener(p->registry, &registry_listener, p);
    if (wl_display_roundtrip(p->display) < 0 ||
        wl_display_roundtrip(p->display) < 0 || !p->presentation) {
        if (p->presentation) wp_presentation_destroy(p->presentation);
        wl_registry_destroy(p->registry);
        free(p);
        SDL_SetError("wp_presentation v1 required; compositor feedback gate unavailable");
        return NULL;
    }
    return p;
}
int egg_present_request(void *opaque, uint64_t frame, uint64_t tick) {
    struct egg_present *p = opaque;
    if (!p->stats.available || p->stats.pending >= CAPACITY || p->stats.lost_samples) {
        SDL_SetError("Wayland feedback unavailable/overflow; refusing unobserved frame counts");
        return -1;
    }
    struct pending *pending = calloc(1, sizeof(*pending));
    if (!pending) { SDL_OutOfMemory(); return -1; }
    pending->owner = p;
    pending->frame = frame;
    pending->tick = tick;
    pending->submitted_ns = monotonic_ns();
    pending->feedback = wp_presentation_feedback(p->presentation, p->surface);
    wp_presentation_feedback_add_listener(pending->feedback, &feedback_listener, pending);
    pending->next = p->head;
    p->head = pending;
    p->stats.requested++;
    p->stats.pending++;
    if (p->stats.pending > p->stats.maximum_pending)
        p->stats.maximum_pending = p->stats.pending;
    return 0;
}
int egg_present_dispatch(void *opaque) {
    struct egg_present *p = opaque;
    if (wl_display_dispatch_pending(p->display) < 0) {
        SDL_SetError("Wayland presentation event dispatch failed");
        return -1;
    }
    return 0;
}
int egg_present_pop(void *opaque, struct egg_sample *sample) {
    struct egg_present *p = opaque;
    if (!p->length) return 0;
    *sample = p->samples[p->begin];
    p->begin = (p->begin + 1) % CAPACITY;
    p->length--;
    return 1;
}
void egg_present_stats(void *opaque, struct egg_stats *stats) {
    *stats = ((struct egg_present *)opaque)->stats;
}
void egg_present_destroy(void *opaque) {
    struct egg_present *p = opaque;
    while (p->head) {
        struct pending *pending = p->head;
        p->head = pending->next;
        wp_presentation_feedback_destroy(pending->feedback);
        free(pending);
    }
    wp_presentation_destroy(p->presentation);
    wl_registry_destroy(p->registry);
    free(p);
}
