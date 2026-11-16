#include "libusb.h"

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__ANDROID__) || defined(__linux__)

#include <linux/usbdevice_fs.h>
#include <poll.h>
#include <pthread.h>
#include <sys/eventfd.h>
#include <sys/ioctl.h>
#include <unistd.h>

#ifndef USB_SPEED_UNKNOWN
#define USB_SPEED_UNKNOWN 0
#define USB_SPEED_LOW 1
#define USB_SPEED_FULL 2
#define USB_SPEED_HIGH 3
#define USB_SPEED_WIRELESS 4
#define USB_SPEED_SUPER 5
#define USB_SPEED_SUPER_PLUS 6
#endif

#define MAX_TRACKED_INTERFACES 32
#define MAX_OPEN_HANDLES 8

struct android_urb_entry {
    struct libusb_transfer *transfer;
    struct usbdevfs_urb *urb;
    struct android_urb_entry *next;
};

struct libusb_device {
    int speed;
    struct libusb_device_descriptor dev_desc;
    int has_dev_desc;
    uint8_t *raw_desc;
    size_t raw_desc_len;
    libusb_device_handle *owner_handle;
};

struct libusb_device_handle {
    libusb_context *ctx;
    int fd;
    int owns_fd;
    int auto_detach;
    int disconnected;
    uint32_t caps;
    uint32_t claimed_mask;
    uint32_t detached_mask;
    struct libusb_device dev;
    pthread_mutex_t lock;
    struct android_urb_entry *urbs;
};

struct libusb_context {
    pthread_mutex_t lock;
    int wakeup_fd;
    int no_device_discovery;
    libusb_device_handle *handles[MAX_OPEN_HANDLES];
};

static int g_no_device_discovery_global = 0;

static void wake_context(libusb_context *ctx) {
    if (ctx && ctx->wakeup_fd >= 0) {
        uint64_t val = 1;
        ssize_t unused = write(ctx->wakeup_fd, &val, sizeof(val));
        (void)unused;
    }
}

static void drain_wakeup(libusb_context *ctx) {
    if (ctx && ctx->wakeup_fd >= 0) {
        uint64_t val = 0;
        while (read(ctx->wakeup_fd, &val, sizeof(val)) > 0) {
        }
    }
}

static int map_errno_to_libusb(int err) {
    switch (err) {
    case 0:
        return LIBUSB_SUCCESS;
    case EINVAL:
        return LIBUSB_ERROR_INVALID_PARAM;
    case EACCES:
    case EPERM:
        return LIBUSB_ERROR_ACCESS;
    case ENOENT:
        return LIBUSB_ERROR_NOT_FOUND;
    case ENODEV:
    case ESHUTDOWN:
    case ENXIO:
        return LIBUSB_ERROR_NO_DEVICE;
    case EBUSY:
        return LIBUSB_ERROR_BUSY;
    case ETIMEDOUT:
        return LIBUSB_ERROR_TIMEOUT;
    case EOVERFLOW:
        return LIBUSB_ERROR_OVERFLOW;
    case EPIPE:
        return LIBUSB_ERROR_PIPE;
    case EINTR:
        return LIBUSB_ERROR_INTERRUPTED;
    case ENOMEM:
        return LIBUSB_ERROR_NO_MEM;
    case ENOTSUP:
    case ENOSYS:
        return LIBUSB_ERROR_NOT_SUPPORTED;
    default:
        return LIBUSB_ERROR_IO;
    }
}

static enum libusb_transfer_status map_urb_status(int status) {
    if (status == 0) {
        return LIBUSB_TRANSFER_COMPLETED;
    }
    int err = status < 0 ? -status : status;
    switch (err) {
    case ENOENT:
    case ECONNRESET:
        return LIBUSB_TRANSFER_CANCELLED;
    case ENODEV:
    case ESHUTDOWN:
    case ENXIO:
        return LIBUSB_TRANSFER_NO_DEVICE;
    case EPIPE:
        return LIBUSB_TRANSFER_STALL;
    case ETIMEDOUT:
        return LIBUSB_TRANSFER_TIMED_OUT;
    case EOVERFLOW:
        return LIBUSB_TRANSFER_OVERFLOW;
    default:
        return LIBUSB_TRANSFER_ERROR;
    }
}

static int map_kernel_speed(int kernel_speed) {
    switch (kernel_speed) {
    case USB_SPEED_LOW:
        return LIBUSB_SPEED_LOW;
    case USB_SPEED_FULL:
        return LIBUSB_SPEED_FULL;
    case USB_SPEED_HIGH:
    case USB_SPEED_WIRELESS:
        return LIBUSB_SPEED_HIGH;
    case USB_SPEED_SUPER:
        return LIBUSB_SPEED_SUPER;
    case USB_SPEED_SUPER_PLUS:
        return LIBUSB_SPEED_SUPER_PLUS;
    default:
        return LIBUSB_SPEED_UNKNOWN;
    }
}

static void parse_device_descriptor_from_raw(struct libusb_device *dev) {
    if (!dev || !dev->raw_desc || dev->raw_desc_len < 18) {
        return;
    }
    size_t pos = 0;
    while (pos + 2 <= dev->raw_desc_len) {
        uint8_t bLength = dev->raw_desc[pos];
        uint8_t bDescriptorType = dev->raw_desc[pos + 1];
        if (bLength < 2 || pos + bLength > dev->raw_desc_len) {
            break;
        }
        if (bDescriptorType == LIBUSB_DT_DEVICE && bLength >= 18) {
            const uint8_t *d = dev->raw_desc + pos;
            dev->dev_desc.bLength = d[0];
            dev->dev_desc.bDescriptorType = d[1];
            dev->dev_desc.bcdUSB = (uint16_t)(d[2] | (d[3] << 8));
            dev->dev_desc.bDeviceClass = d[4];
            dev->dev_desc.bDeviceSubClass = d[5];
            dev->dev_desc.bDeviceProtocol = d[6];
            dev->dev_desc.bMaxPacketSize0 = d[7];
            dev->dev_desc.idVendor = (uint16_t)(d[8] | (d[9] << 8));
            dev->dev_desc.idProduct = (uint16_t)(d[10] | (d[11] << 8));
            dev->dev_desc.bcdDevice = (uint16_t)(d[12] | (d[13] << 8));
            dev->dev_desc.iManufacturer = d[14];
            dev->dev_desc.iProduct = d[15];
            dev->dev_desc.iSerialNumber = d[16];
            dev->dev_desc.bNumConfigurations = d[17];
            dev->has_dev_desc = 1;
            return;
        }
        pos += bLength;
    }
}

static void read_raw_descriptors_from_fd(int fd, uint8_t **out_buf, size_t *out_len) {
    *out_buf = NULL;
    *out_len = 0;
    if (fd < 0) {
        return;
    }
    if (lseek(fd, 0, SEEK_SET) == (off_t)-1) {
        return;
    }

    size_t cap = 4096;
    size_t len = 0;
    uint8_t *buf = (uint8_t *)malloc(cap);
    if (!buf) {
        return;
    }

    for (;;) {
        if (len + 1024 > cap) {
            if (cap >= 65536) {
                break;
            }
            size_t new_cap = cap * 2;
            uint8_t *nb = (uint8_t *)realloc(buf, new_cap);
            if (!nb) {
                break;
            }
            buf = nb;
            cap = new_cap;
        }
        ssize_t n = read(fd, buf + len, cap - len);
        if (n > 0) {
            len += (size_t)n;
        } else if (n < 0 && errno == EINTR) {
            continue;
        } else {
            break;
        }
    }

    if (len == 0) {
        free(buf);
        return;
    }
    *out_buf = buf;
    *out_len = len;
}

int LIBUSB_CALL libusb_set_option(libusb_context *ctx, enum libusb_option option, ...) {
    va_list ap;
    va_start(ap, option);
    if (option == LIBUSB_OPTION_NO_DEVICE_DISCOVERY) {
        if (ctx) {
            ctx->no_device_discovery = 1;
        } else {
            g_no_device_discovery_global = 1;
        }
        va_end(ap);
        return LIBUSB_SUCCESS;
    }
    if (option == LIBUSB_OPTION_LOG_LEVEL) {
        (void)va_arg(ap, int);
        va_end(ap);
        return LIBUSB_SUCCESS;
    }
    va_end(ap);
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int LIBUSB_CALL libusb_init(libusb_context **ctx) {
    if (!ctx) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }
    libusb_context *c = (libusb_context *)calloc(1, sizeof(libusb_context));
    if (!c) {
        return LIBUSB_ERROR_NO_MEM;
    }
    pthread_mutex_init(&c->lock, NULL);
    c->wakeup_fd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    c->no_device_discovery = g_no_device_discovery_global;
    *ctx = c;
    return LIBUSB_SUCCESS;
}

void LIBUSB_CALL libusb_exit(libusb_context *ctx) {
    if (!ctx) {
        return;
    }
    if (ctx->wakeup_fd >= 0) {
        close(ctx->wakeup_fd);
        ctx->wakeup_fd = -1;
    }
    pthread_mutex_destroy(&ctx->lock);
    free(ctx);
}

int LIBUSB_CALL libusb_wrap_sys_device(
    libusb_context *ctx,
    intptr_t sys_dev,
    libusb_device_handle **dev_handle
) {
    if (!ctx || !dev_handle || sys_dev < 0) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }

    int fd = (int)sys_dev;
    libusb_device_handle *h = (libusb_device_handle *)calloc(1, sizeof(libusb_device_handle));
    if (!h) {
        return LIBUSB_ERROR_NO_MEM;
    }

    h->ctx = ctx;
    h->fd = fd;
    h->owns_fd = 0; /* Caller (Android UsbDeviceConnection) owns fd lifetime. */
    h->auto_detach = 0;
    h->dev.owner_handle = h;
    pthread_mutex_init(&h->lock, NULL);

    uint32_t caps = 0;
    if (ioctl(fd, USBDEVFS_GET_CAPABILITIES, &caps) == 0) {
        h->caps = caps;
    }

    int kspeed = ioctl(fd, USBDEVFS_GET_SPEED);
    if (kspeed >= 0) {
        h->dev.speed = map_kernel_speed(kspeed);
    } else {
        h->dev.speed = LIBUSB_SPEED_UNKNOWN;
    }

    read_raw_descriptors_from_fd(fd, &h->dev.raw_desc, &h->dev.raw_desc_len);
    parse_device_descriptor_from_raw(&h->dev);

    if (h->dev.speed == LIBUSB_SPEED_UNKNOWN && h->dev.has_dev_desc) {
        h->dev.speed = (h->dev.dev_desc.bcdUSB >= 0x0300)
            ? LIBUSB_SPEED_SUPER
            : (h->dev.dev_desc.bcdUSB >= 0x0200 ? LIBUSB_SPEED_HIGH : LIBUSB_SPEED_FULL);
    }

    pthread_mutex_lock(&ctx->lock);
    int slot_found = 0;
    for (int i = 0; i < MAX_OPEN_HANDLES; ++i) {
        if (ctx->handles[i] == NULL) {
            ctx->handles[i] = h;
            slot_found = 1;
            break;
        }
    }
    pthread_mutex_unlock(&ctx->lock);

    if (!slot_found) {
        free(h->dev.raw_desc);
        pthread_mutex_destroy(&h->lock);
        free(h);
        return LIBUSB_ERROR_NO_MEM;
    }

    *dev_handle = h;
    wake_context(ctx);
    return LIBUSB_SUCCESS;
}

void LIBUSB_CALL libusb_close(libusb_device_handle *dev_handle) {
    if (!dev_handle) {
        return;
    }
    libusb_context *ctx = dev_handle->ctx;
    if (ctx) {
        pthread_mutex_lock(&ctx->lock);
        for (int i = 0; i < MAX_OPEN_HANDLES; ++i) {
            if (ctx->handles[i] == dev_handle) {
                ctx->handles[i] = NULL;
            }
        }
        pthread_mutex_unlock(&ctx->lock);
        wake_context(ctx);
    }

    /* Release any interfaces still claimed and re-attach kernel drivers if auto-detached. */
    for (int iface = 0; iface < MAX_TRACKED_INTERFACES; ++iface) {
        if (dev_handle->claimed_mask & (1u << iface)) {
            (void)libusb_release_interface(dev_handle, iface);
        }
    }

    pthread_mutex_lock(&dev_handle->lock);
    struct android_urb_entry *cur = dev_handle->urbs;
    dev_handle->urbs = NULL;
    pthread_mutex_unlock(&dev_handle->lock);

    while (cur) {
        struct android_urb_entry *next = cur->next;
        if (cur->urb) {
            ioctl(dev_handle->fd, USBDEVFS_DISCARDURB, cur->urb);
            free(cur->urb);
        }
        free(cur);
        cur = next;
    }

    if (dev_handle->owns_fd && dev_handle->fd >= 0) {
        close(dev_handle->fd);
    }
    free(dev_handle->dev.raw_desc);
    pthread_mutex_destroy(&dev_handle->lock);
    free(dev_handle);
}

libusb_device *LIBUSB_CALL libusb_get_device(libusb_device_handle *dev_handle) {
    return dev_handle ? &dev_handle->dev : NULL;
}

int LIBUSB_CALL libusb_get_device_speed(libusb_device *dev) {
    return dev ? dev->speed : LIBUSB_SPEED_UNKNOWN;
}

int LIBUSB_CALL libusb_android_set_raw_descriptors(
    libusb_device_handle *dev_handle,
    const uint8_t *raw_desc,
    size_t len
) {
    if (!dev_handle || !raw_desc || len == 0) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }
    uint8_t *copy = (uint8_t *)malloc(len);
    if (!copy) {
        return LIBUSB_ERROR_NO_MEM;
    }
    memcpy(copy, raw_desc, len);

    pthread_mutex_lock(&dev_handle->lock);
    free(dev_handle->dev.raw_desc);
    dev_handle->dev.raw_desc = copy;
    dev_handle->dev.raw_desc_len = len;
    dev_handle->dev.has_dev_desc = 0;
    parse_device_descriptor_from_raw(&dev_handle->dev);
    pthread_mutex_unlock(&dev_handle->lock);
    return LIBUSB_SUCCESS;
}

const uint8_t *LIBUSB_CALL libusb_android_get_raw_descriptors(
    libusb_device_handle *dev_handle,
    size_t *out_len
) {
    if (out_len) {
        *out_len = 0;
    }
    if (!dev_handle) {
        return NULL;
    }
    if (out_len) {
        *out_len = dev_handle->dev.raw_desc_len;
    }
    return dev_handle->dev.raw_desc;
}

int LIBUSB_CALL libusb_get_device_descriptor(
    libusb_device *dev,
    struct libusb_device_descriptor *desc
) {
    if (!dev || !desc) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }
    if (!dev->has_dev_desc) {
        return LIBUSB_ERROR_NOT_FOUND;
    }
    *desc = dev->dev_desc;
    return LIBUSB_SUCCESS;
}

struct config_alloc_backing {
    struct libusb_config_descriptor cfg;
    uint8_t *raw_copy;
};

int LIBUSB_CALL libusb_get_active_config_descriptor(
    libusb_device *dev,
    struct libusb_config_descriptor **config
) {
    if (!dev || !config) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }
    *config = NULL;
    if (!dev->raw_desc || dev->raw_desc_len < 9) {
        return LIBUSB_ERROR_NOT_FOUND;
    }

    const uint8_t *raw = dev->raw_desc;
    size_t raw_len = dev->raw_desc_len;
    size_t cfg_start = 0;
    size_t cfg_total = 0;
    int found_cfg = 0;

    size_t pos = 0;
    while (pos + 2 <= raw_len) {
        uint8_t bLength = raw[pos];
        uint8_t bType = raw[pos + 1];
        if (bLength < 2 || pos + bLength > raw_len) {
            break;
        }
        if (bType == LIBUSB_DT_CONFIG && bLength >= 9) {
            cfg_start = pos;
            cfg_total = (size_t)(raw[pos + 2] | (raw[pos + 3] << 8));
            if (cfg_total == 0 || cfg_start + cfg_total > raw_len) {
                cfg_total = raw_len - cfg_start;
            }
            found_cfg = 1;
            break;
        }
        pos += bLength;
    }

    if (!found_cfg || cfg_total < 9) {
        return LIBUSB_ERROR_NOT_FOUND;
    }

    struct config_alloc_backing *backing =
        (struct config_alloc_backing *)calloc(1, sizeof(struct config_alloc_backing));
    if (!backing) {
        return LIBUSB_ERROR_NO_MEM;
    }
    backing->raw_copy = (uint8_t *)malloc(cfg_total);
    if (!backing->raw_copy) {
        free(backing);
        return LIBUSB_ERROR_NO_MEM;
    }
    memcpy(backing->raw_copy, raw + cfg_start, cfg_total);

    const uint8_t *c = backing->raw_copy;
    backing->cfg.bLength = c[0];
    backing->cfg.bDescriptorType = c[1];
    backing->cfg.wTotalLength = (uint16_t)(c[2] | (c[3] << 8));
    backing->cfg.bNumInterfaces = c[4];
    backing->cfg.bConfigurationValue = c[5];
    backing->cfg.iConfiguration = c[6];
    backing->cfg.bmAttributes = c[7];
    backing->cfg.MaxPower = c[8];

    int max_iface_num = -1;
    int total_altsettings = 0;
    int total_endpoints = 0;

    pos = c[0];
    while (pos + 2 <= cfg_total) {
        uint8_t bLen = c[pos];
        uint8_t bType = c[pos + 1];
        if (bLen < 2 || pos + bLen > cfg_total) {
            break;
        }
        if (bType == LIBUSB_DT_INTERFACE && bLen >= 9) {
            int iface_num = c[pos + 2];
            if (iface_num > max_iface_num) {
                max_iface_num = iface_num;
            }
            total_altsettings++;
        } else if (bType == LIBUSB_DT_ENDPOINT && bLen >= 7) {
            total_endpoints++;
        }
        pos += bLen;
    }

    int num_ifaces = (max_iface_num >= 0) ? (max_iface_num + 1) : 0;
    struct libusb_interface *ifaces = num_ifaces > 0
        ? (struct libusb_interface *)calloc((size_t)num_ifaces, sizeof(struct libusb_interface))
        : NULL;
    struct libusb_interface_descriptor *alts = total_altsettings > 0
        ? (struct libusb_interface_descriptor *)calloc((size_t)total_altsettings, sizeof(struct libusb_interface_descriptor))
        : NULL;
    struct libusb_endpoint_descriptor *eps = total_endpoints > 0
        ? (struct libusb_endpoint_descriptor *)calloc((size_t)total_endpoints, sizeof(struct libusb_endpoint_descriptor))
        : NULL;

    if ((num_ifaces > 0 && !ifaces) ||
        (total_altsettings > 0 && !alts) ||
        (total_endpoints > 0 && !eps)) {
        free(ifaces);
        free(alts);
        free(eps);
        free(backing->raw_copy);
        free(backing);
        return LIBUSB_ERROR_NO_MEM;
    }

    int *iface_alt_counts = num_ifaces > 0 ? (int *)calloc((size_t)num_ifaces, sizeof(int)) : NULL;
    if (num_ifaces > 0 && !iface_alt_counts) {
        free(ifaces);
        free(alts);
        free(eps);
        free(backing->raw_copy);
        free(backing);
        return LIBUSB_ERROR_NO_MEM;
    }

    pos = c[0];
    while (pos + 2 <= cfg_total) {
        uint8_t bLen = c[pos];
        uint8_t bType = c[pos + 1];
        if (bLen < 2 || pos + bLen > cfg_total) {
            break;
        }
        if (bType == LIBUSB_DT_INTERFACE && bLen >= 9) {
            int iface_num = c[pos + 2];
            if (iface_num >= 0 && iface_num < num_ifaces) {
                iface_alt_counts[iface_num]++;
            }
        }
        pos += bLen;
    }

    int alt_offset = 0;
    for (int i = 0; i < num_ifaces; ++i) {
        ifaces[i].num_altsetting = 0;
        ifaces[i].altsetting = (iface_alt_counts[i] > 0) ? &alts[alt_offset] : NULL;
        alt_offset += iface_alt_counts[i];
    }
    free(iface_alt_counts);

    int ep_cursor = 0;
    struct libusb_interface_descriptor *cur_alt = NULL;
    struct libusb_endpoint_descriptor *cur_ep = NULL;

    pos = c[0];
    while (pos + 2 <= cfg_total) {
        uint8_t bLen = c[pos];
        uint8_t bType = c[pos + 1];
        if (bLen < 2 || pos + bLen > cfg_total) {
            break;
        }
        if (bType == LIBUSB_DT_INTERFACE && bLen >= 9) {
            int iface_num = c[pos + 2];
            struct libusb_interface *iface = &ifaces[iface_num];
            struct libusb_interface_descriptor *dst =
                (struct libusb_interface_descriptor *)&iface->altsetting[iface->num_altsetting++];
            dst->bLength = c[pos + 0];
            dst->bDescriptorType = c[pos + 1];
            dst->bInterfaceNumber = c[pos + 2];
            dst->bAlternateSetting = c[pos + 3];
            dst->bNumEndpoints = c[pos + 4];
            dst->bInterfaceClass = c[pos + 5];
            dst->bInterfaceSubClass = c[pos + 6];
            dst->bInterfaceProtocol = c[pos + 7];
            dst->iInterface = c[pos + 8];
            dst->endpoint = NULL;
            dst->extra = NULL;
            dst->extra_length = 0;
            cur_alt = dst;
            cur_ep = NULL;
        } else if (bType == LIBUSB_DT_ENDPOINT && bLen >= 7) {
            struct libusb_endpoint_descriptor *ep = &eps[ep_cursor++];
            ep->bLength = c[pos + 0];
            ep->bDescriptorType = c[pos + 1];
            ep->bEndpointAddress = c[pos + 2];
            ep->bmAttributes = c[pos + 3];
            ep->wMaxPacketSize = (uint16_t)(c[pos + 4] | (c[pos + 5] << 8));
            ep->bInterval = c[pos + 6];
            ep->bRefresh = (bLen >= 8) ? c[pos + 7] : 0;
            ep->bSynchAddress = (bLen >= 9) ? c[pos + 8] : 0;
            ep->extra = NULL;
            ep->extra_length = 0;
            if (cur_alt) {
                if (!cur_alt->endpoint) {
                    cur_alt->endpoint = ep;
                }
            }
            cur_ep = ep;
        } else {
            if (cur_ep) {
                if (!cur_ep->extra) {
                    cur_ep->extra = c + pos;
                }
                cur_ep->extra_length += bLen;
            } else if (cur_alt) {
                if (!cur_alt->extra) {
                    cur_alt->extra = c + pos;
                }
                cur_alt->extra_length += bLen;
            } else {
                if (!backing->cfg.extra) {
                    backing->cfg.extra = c + pos;
                }
                backing->cfg.extra_length += bLen;
            }
        }
        pos += bLen;
    }

    backing->cfg.bNumInterfaces = (uint8_t)num_ifaces;
    backing->cfg.interface = ifaces;
    *config = &backing->cfg;
    return LIBUSB_SUCCESS;
}

void LIBUSB_CALL libusb_free_config_descriptor(struct libusb_config_descriptor *config) {
    if (!config) {
        return;
    }
    struct config_alloc_backing *backing = (struct config_alloc_backing *)config;
    if (config->interface) {
        const struct libusb_interface_descriptor *min_alt = NULL;
        const struct libusb_endpoint_descriptor *min_ep = NULL;
        for (int i = 0; i < config->bNumInterfaces; ++i) {
            const struct libusb_interface *iface = &config->interface[i];
            if (iface->altsetting && (!min_alt || iface->altsetting < min_alt)) {
                min_alt = iface->altsetting;
            }
            for (int a = 0; a < iface->num_altsetting; ++a) {
                const struct libusb_endpoint_descriptor *ep = iface->altsetting[a].endpoint;
                if (ep && (!min_ep || ep < min_ep)) {
                    min_ep = ep;
                }
            }
        }
        free((void *)min_ep);
        free((void *)min_alt);
        free((void *)config->interface);
    }
    free(backing->raw_copy);
    free(backing);
}

int LIBUSB_CALL libusb_set_auto_detach_kernel_driver(libusb_device_handle *dev_handle, int enable) {
    if (!dev_handle) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }
    dev_handle->auto_detach = enable ? 1 : 0;
    return LIBUSB_SUCCESS;
}

int LIBUSB_CALL libusb_kernel_driver_active(libusb_device_handle *dev_handle, int interface_number) {
    if (!dev_handle || interface_number < 0) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }
    struct usbdevfs_getdriver getdrv;
    memset(&getdrv, 0, sizeof(getdrv));
    getdrv.interface = (unsigned int)interface_number;
    if (ioctl(dev_handle->fd, USBDEVFS_GETDRIVER, &getdrv) == 0) {
        if (strcmp(getdrv.driver, "usbfs") == 0) {
            return 0;
        }
        return 1;
    }
    if (errno == ENODATA) {
        return 0;
    }
    return map_errno_to_libusb(errno);
}

int LIBUSB_CALL libusb_detach_kernel_driver(libusb_device_handle *dev_handle, int interface_number) {
    if (!dev_handle || interface_number < 0) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }
    struct usbdevfs_ioctl cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.ifno = interface_number;
    cmd.ioctl_code = USBDEVFS_DISCONNECT;
    cmd.data = NULL;
    if (ioctl(dev_handle->fd, USBDEVFS_IOCTL, &cmd) == 0) {
        if (interface_number < MAX_TRACKED_INTERFACES) {
            dev_handle->detached_mask |= (1u << interface_number);
        }
        return LIBUSB_SUCCESS;
    }
    if (errno == ENODATA) {
        return LIBUSB_ERROR_NOT_FOUND;
    }
    return map_errno_to_libusb(errno);
}

int LIBUSB_CALL libusb_attach_kernel_driver(libusb_device_handle *dev_handle, int interface_number) {
    if (!dev_handle || interface_number < 0) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }
    struct usbdevfs_ioctl cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.ifno = interface_number;
    cmd.ioctl_code = USBDEVFS_CONNECT;
    cmd.data = NULL;
    if (ioctl(dev_handle->fd, USBDEVFS_IOCTL, &cmd) == 0) {
        if (interface_number < MAX_TRACKED_INTERFACES) {
            dev_handle->detached_mask &= ~(1u << interface_number);
        }
        return LIBUSB_SUCCESS;
    }
    return map_errno_to_libusb(errno);
}

int LIBUSB_CALL libusb_claim_interface(libusb_device_handle *dev_handle, int interface_number) {
    if (!dev_handle || interface_number < 0) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }

    if (dev_handle->auto_detach) {
        int was_active = libusb_kernel_driver_active(dev_handle, interface_number);
        struct usbdevfs_disconnect_claim dc;
        memset(&dc, 0, sizeof(dc));
        dc.interface = (unsigned int)interface_number;
        dc.flags = 0;
        if (ioctl(dev_handle->fd, USBDEVFS_DISCONNECT_CLAIM, &dc) == 0) {
            if (interface_number < MAX_TRACKED_INTERFACES) {
                dev_handle->claimed_mask |= (1u << interface_number);
                if (was_active == 1) {
                    dev_handle->detached_mask |= (1u << interface_number);
                }
            }
            return LIBUSB_SUCCESS;
        }
        if (errno != ENOTTY && errno != EINVAL) {
            return map_errno_to_libusb(errno);
        }
        int drc = libusb_detach_kernel_driver(dev_handle, interface_number);
        if (drc != LIBUSB_SUCCESS && drc != LIBUSB_ERROR_NOT_FOUND) {
            return drc;
        }
    }

    unsigned int iface = (unsigned int)interface_number;
    if (ioctl(dev_handle->fd, USBDEVFS_CLAIMINTERFACE, &iface) == 0) {
        if (interface_number < MAX_TRACKED_INTERFACES) {
            dev_handle->claimed_mask |= (1u << interface_number);
        }
        return LIBUSB_SUCCESS;
    }
    return map_errno_to_libusb(errno);
}

int LIBUSB_CALL libusb_release_interface(libusb_device_handle *dev_handle, int interface_number) {
    if (!dev_handle || interface_number < 0) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }
    unsigned int iface = (unsigned int)interface_number;
    int rc = LIBUSB_SUCCESS;
    if (ioctl(dev_handle->fd, USBDEVFS_RELEASEINTERFACE, &iface) < 0) {
        rc = map_errno_to_libusb(errno);
    }
    if (interface_number < MAX_TRACKED_INTERFACES) {
        dev_handle->claimed_mask &= ~(1u << interface_number);
        if (dev_handle->auto_detach && (dev_handle->detached_mask & (1u << interface_number))) {
            (void)libusb_attach_kernel_driver(dev_handle, interface_number);
        }
    }
    return rc;
}

int LIBUSB_CALL libusb_set_interface_alt_setting(
    libusb_device_handle *dev_handle,
    int interface_number,
    int alternate_setting
) {
    if (!dev_handle || interface_number < 0 || alternate_setting < 0) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }
    struct usbdevfs_setinterface setintf;
    setintf.interface = (unsigned int)interface_number;
    setintf.altsetting = (unsigned int)alternate_setting;
    if (ioctl(dev_handle->fd, USBDEVFS_SETINTERFACE, &setintf) == 0) {
        return LIBUSB_SUCCESS;
    }
    return map_errno_to_libusb(errno);
}

int LIBUSB_CALL libusb_clear_halt(libusb_device_handle *dev_handle, unsigned char endpoint) {
    if (!dev_handle) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }
    unsigned int ep = (unsigned int)endpoint;
    if (ioctl(dev_handle->fd, USBDEVFS_CLEAR_HALT, &ep) == 0) {
        return LIBUSB_SUCCESS;
    }
    return map_errno_to_libusb(errno);
}

int LIBUSB_CALL libusb_reset_device(libusb_device_handle *dev_handle) {
    if (!dev_handle) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }
    if (ioctl(dev_handle->fd, USBDEVFS_RESET) == 0) {
        return LIBUSB_SUCCESS;
    }
    return map_errno_to_libusb(errno);
}

int LIBUSB_CALL libusb_control_transfer(
    libusb_device_handle *dev_handle,
    uint8_t bmRequestType,
    uint8_t bRequest,
    uint16_t wValue,
    uint16_t wIndex,
    unsigned char *data,
    uint16_t wLength,
    unsigned int timeout
) {
    if (!dev_handle) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }
    struct usbdevfs_ctrltransfer ctrl;
    ctrl.bRequestType = bmRequestType;
    ctrl.bRequest = bRequest;
    ctrl.wValue = wValue;
    ctrl.wIndex = wIndex;
    ctrl.wLength = wLength;
    ctrl.timeout = timeout > 0 ? timeout : 1000;
    ctrl.data = data;

    int rc = ioctl(dev_handle->fd, USBDEVFS_CONTROL, &ctrl);
    if (rc >= 0) {
        return rc;
    }
    return map_errno_to_libusb(errno);
}

struct libusb_transfer *LIBUSB_CALL libusb_alloc_transfer(int iso_packets) {
    if (iso_packets < 0) {
        return NULL;
    }
    size_t extra_iso = (iso_packets > 1)
        ? (size_t)(iso_packets - 1) * sizeof(struct libusb_iso_packet_descriptor)
        : 0;
    struct libusb_transfer *t =
        (struct libusb_transfer *)calloc(1, sizeof(struct libusb_transfer) + extra_iso);
    if (t) {
        t->num_iso_packets = iso_packets;
    }
    return t;
}

void LIBUSB_CALL libusb_free_transfer(struct libusb_transfer *transfer) {
    free(transfer);
}

int LIBUSB_CALL libusb_submit_transfer(struct libusb_transfer *transfer) {
    if (!transfer || !transfer->dev_handle) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }
    libusb_device_handle *h = transfer->dev_handle;
    if (h->disconnected) {
        return LIBUSB_ERROR_NO_DEVICE;
    }

    int num_pkts = (transfer->type == LIBUSB_TRANSFER_TYPE_ISOCHRONOUS)
        ? transfer->num_iso_packets
        : 0;
    if (transfer->type == LIBUSB_TRANSFER_TYPE_ISOCHRONOUS && num_pkts <= 0) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }

    size_t urb_size = sizeof(struct usbdevfs_urb) +
        (size_t)num_pkts * sizeof(struct usbdevfs_iso_packet_desc);
    struct usbdevfs_urb *urb = (struct usbdevfs_urb *)calloc(1, urb_size);
    struct android_urb_entry *entry =
        (struct android_urb_entry *)calloc(1, sizeof(struct android_urb_entry));
    if (!urb || !entry) {
        free(urb);
        free(entry);
        return LIBUSB_ERROR_NO_MEM;
    }

    entry->transfer = transfer;
    entry->urb = urb;

    switch (transfer->type) {
    case LIBUSB_TRANSFER_TYPE_ISOCHRONOUS:
        urb->type = USBDEVFS_URB_TYPE_ISO;
        urb->flags = USBDEVFS_URB_ISO_ASAP;
        urb->number_of_packets = num_pkts;
        for (int i = 0; i < num_pkts; ++i) {
            urb->iso_frame_desc[i].length = transfer->iso_packet_desc[i].length;
            urb->iso_frame_desc[i].actual_length = 0;
            urb->iso_frame_desc[i].status = 0;
        }
        break;
    case LIBUSB_TRANSFER_TYPE_INTERRUPT:
        urb->type = USBDEVFS_URB_TYPE_INTERRUPT;
        break;
    case LIBUSB_TRANSFER_TYPE_BULK:
        urb->type = USBDEVFS_URB_TYPE_BULK;
        break;
    default:
        free(urb);
        free(entry);
        return LIBUSB_ERROR_NOT_SUPPORTED;
    }

    urb->endpoint = transfer->endpoint;
    urb->buffer = transfer->buffer;
    urb->buffer_length = transfer->length;
    urb->usercontext = entry;

    pthread_mutex_lock(&h->lock);
    entry->next = h->urbs;
    h->urbs = entry;
    pthread_mutex_unlock(&h->lock);

    if (ioctl(h->fd, USBDEVFS_SUBMITURB, urb) < 0) {
        int err = errno;
        pthread_mutex_lock(&h->lock);
        struct android_urb_entry **pp = &h->urbs;
        while (*pp) {
            if (*pp == entry) {
                *pp = entry->next;
                break;
            }
            pp = &(*pp)->next;
        }
        pthread_mutex_unlock(&h->lock);
        free(urb);
        free(entry);
        if (err == ENODEV || err == ESHUTDOWN || err == ENXIO) {
            h->disconnected = 1;
        }
        return map_errno_to_libusb(err);
    }

    return LIBUSB_SUCCESS;
}

int LIBUSB_CALL libusb_cancel_transfer(struct libusb_transfer *transfer) {
    if (!transfer || !transfer->dev_handle) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }
    libusb_device_handle *h = transfer->dev_handle;
    struct usbdevfs_urb *target_urb = NULL;

    pthread_mutex_lock(&h->lock);
    struct android_urb_entry *cur = h->urbs;
    while (cur) {
        if (cur->transfer == transfer) {
            target_urb = cur->urb;
            break;
        }
        cur = cur->next;
    }
    pthread_mutex_unlock(&h->lock);

    if (!target_urb) {
        return LIBUSB_ERROR_NOT_FOUND;
    }

    if (ioctl(h->fd, USBDEVFS_DISCARDURB, target_urb) < 0) {
        if (errno == EINVAL) {
            return LIBUSB_ERROR_NOT_FOUND;
        }
        return map_errno_to_libusb(errno);
    }
    wake_context(h->ctx);
    return LIBUSB_SUCCESS;
}

static int reap_handle_urbs(libusb_device_handle *h) {
    int reaped_count = 0;
    for (;;) {
        struct usbdevfs_urb *reaped_urb = NULL;
        if (ioctl(h->fd, USBDEVFS_REAPURBNDELAY, &reaped_urb) < 0) {
            if (errno == EAGAIN) {
                break;
            }
            if (errno == ENODEV || errno == ESHUTDOWN || errno == ENXIO) {
                h->disconnected = 1;
                return LIBUSB_ERROR_NO_DEVICE;
            }
            if (errno == EINTR) {
                continue;
            }
            break;
        }

        if (!reaped_urb) {
            break;
        }

        struct android_urb_entry *entry = (struct android_urb_entry *)reaped_urb->usercontext;
        struct libusb_transfer *transfer = NULL;

        pthread_mutex_lock(&h->lock);
        struct android_urb_entry **pp = &h->urbs;
        while (*pp) {
            if (*pp == entry) {
                *pp = entry->next;
                transfer = entry->transfer;
                break;
            }
            pp = &(*pp)->next;
        }
        pthread_mutex_unlock(&h->lock);

        if (transfer) {
            transfer->status = map_urb_status(reaped_urb->status);
            transfer->actual_length = reaped_urb->actual_length;
            if (transfer->type == LIBUSB_TRANSFER_TYPE_ISOCHRONOUS) {
                int np = transfer->num_iso_packets;
                if (reaped_urb->number_of_packets < np) {
                    np = reaped_urb->number_of_packets;
                }
                for (int i = 0; i < np; ++i) {
                    transfer->iso_packet_desc[i].actual_length =
                        reaped_urb->iso_frame_desc[i].actual_length;
                    transfer->iso_packet_desc[i].status =
                        map_urb_status((int)reaped_urb->iso_frame_desc[i].status);
                }
            }
            free(reaped_urb);
            free(entry);
            reaped_count++;

            if (transfer->callback) {
                transfer->callback(transfer);
            }
        } else {
            free(reaped_urb);
            free(entry);
        }
    }
    return reaped_count;
}

int LIBUSB_CALL libusb_handle_events_timeout_completed(
    libusb_context *ctx,
    struct timeval *tv,
    int *completed
) {
    if (!ctx) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }

    if (completed && *completed) {
        return LIBUSB_SUCCESS;
    }

    libusb_device_handle *handles[MAX_OPEN_HANDLES];
    int handle_count = 0;

    pthread_mutex_lock(&ctx->lock);
    for (int i = 0; i < MAX_OPEN_HANDLES; ++i) {
        if (ctx->handles[i] != NULL) {
            handles[handle_count++] = ctx->handles[i];
        }
    }
    pthread_mutex_unlock(&ctx->lock);

    /* Fast path: reap any already-completed URBs before blocking in poll(). */
    int any_reaped = 0;
    for (int i = 0; i < handle_count; ++i) {
        int r = reap_handle_urbs(handles[i]);
        if (r < 0) {
            return r;
        }
        if (r > 0) {
            any_reaped = 1;
        }
    }

    if (any_reaped || (completed && *completed)) {
        return LIBUSB_SUCCESS;
    }

    struct pollfd pfds[MAX_OPEN_HANDLES + 1];
    nfds_t nfds = 0;
    int wakeup_index = -1;
    if (ctx->wakeup_fd >= 0) {
        wakeup_index = (int)nfds;
        pfds[nfds].fd = ctx->wakeup_fd;
        pfds[nfds].events = POLLIN;
        pfds[nfds].revents = 0;
        nfds++;
    }

    int first_handle_pfd = (int)nfds;
    for (int i = 0; i < handle_count; ++i) {
        pfds[nfds].fd = handles[i]->fd;
        pfds[nfds].events = POLLOUT;
        pfds[nfds].revents = 0;
        nfds++;
    }

    int timeout_ms = -1;
    if (tv) {
        long long ms = (long long)tv->tv_sec * 1000LL + (long long)(tv->tv_usec + 999) / 1000LL;
        if (ms < 0) ms = 0;
        if (ms > 60000) ms = 60000;
        timeout_ms = (int)ms;
    }

    if (nfds == 0) {
        return LIBUSB_SUCCESS;
    }

    int prc = poll(pfds, nfds, timeout_ms);
    if (prc < 0) {
        if (errno == EINTR) {
            return LIBUSB_SUCCESS;
        }
        return map_errno_to_libusb(errno);
    }

    if (wakeup_index >= 0 && (pfds[wakeup_index].revents & POLLIN)) {
        drain_wakeup(ctx);
    }

    for (int i = 0; i < handle_count; ++i) {
        short rev = pfds[first_handle_pfd + i].revents;
        if (rev & (POLLOUT | POLLERR | POLLHUP)) {
            int r = reap_handle_urbs(handles[i]);
            if (r < 0) {
                return r;
            }
            if ((rev & (POLLERR | POLLHUP)) && handles[i]->disconnected) {
                return LIBUSB_ERROR_NO_DEVICE;
            }
        }
    }

    return LIBUSB_SUCCESS;
}

int LIBUSB_CALL libusb_handle_events_completed(libusb_context *ctx, int *completed) {
    struct timeval tv;
    tv.tv_sec = 0;
    tv.tv_usec = 50000;
    return libusb_handle_events_timeout_completed(ctx, &tv, completed);
}

#else /* Non-Linux / Non-Android build stubs */

struct libusb_context {
    int unused;
};

struct libusb_device {
    int unused;
};

struct libusb_device_handle {
    int unused;
};

int LIBUSB_CALL libusb_set_option(libusb_context *ctx, enum libusb_option option, ...) {
    (void)ctx;
    (void)option;
    return LIBUSB_SUCCESS;
}

int LIBUSB_CALL libusb_init(libusb_context **ctx) {
    if (!ctx) return LIBUSB_ERROR_INVALID_PARAM;
    *ctx = (libusb_context *)calloc(1, sizeof(libusb_context));
    return *ctx ? LIBUSB_SUCCESS : LIBUSB_ERROR_NO_MEM;
}

void LIBUSB_CALL libusb_exit(libusb_context *ctx) {
    free(ctx);
}

int LIBUSB_CALL libusb_wrap_sys_device(libusb_context *ctx, intptr_t sys_dev, libusb_device_handle **dev_handle) {
    (void)ctx;
    (void)sys_dev;
    if (dev_handle) *dev_handle = NULL;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

void LIBUSB_CALL libusb_close(libusb_device_handle *dev_handle) {
    free(dev_handle);
}

libusb_device *LIBUSB_CALL libusb_get_device(libusb_device_handle *dev_handle) {
    (void)dev_handle;
    return NULL;
}

int LIBUSB_CALL libusb_get_device_speed(libusb_device *dev) {
    (void)dev;
    return LIBUSB_SPEED_UNKNOWN;
}

int LIBUSB_CALL libusb_get_device_descriptor(libusb_device *dev, struct libusb_device_descriptor *desc) {
    (void)dev;
    (void)desc;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int LIBUSB_CALL libusb_get_active_config_descriptor(libusb_device *dev, struct libusb_config_descriptor **config) {
    (void)dev;
    if (config) *config = NULL;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

void LIBUSB_CALL libusb_free_config_descriptor(struct libusb_config_descriptor *config) {
    free(config);
}

int LIBUSB_CALL libusb_set_auto_detach_kernel_driver(libusb_device_handle *dev_handle, int enable) {
    (void)dev_handle;
    (void)enable;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int LIBUSB_CALL libusb_kernel_driver_active(libusb_device_handle *dev_handle, int interface_number) {
    (void)dev_handle;
    (void)interface_number;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int LIBUSB_CALL libusb_detach_kernel_driver(libusb_device_handle *dev_handle, int interface_number) {
    (void)dev_handle;
    (void)interface_number;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int LIBUSB_CALL libusb_attach_kernel_driver(libusb_device_handle *dev_handle, int interface_number) {
    (void)dev_handle;
    (void)interface_number;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int LIBUSB_CALL libusb_claim_interface(libusb_device_handle *dev_handle, int interface_number) {
    (void)dev_handle;
    (void)interface_number;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int LIBUSB_CALL libusb_release_interface(libusb_device_handle *dev_handle, int interface_number) {
    (void)dev_handle;
    (void)interface_number;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int LIBUSB_CALL libusb_set_interface_alt_setting(libusb_device_handle *dev_handle, int interface_number, int alternate_setting) {
    (void)dev_handle;
    (void)interface_number;
    (void)alternate_setting;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int LIBUSB_CALL libusb_clear_halt(libusb_device_handle *dev_handle, unsigned char endpoint) {
    (void)dev_handle;
    (void)endpoint;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int LIBUSB_CALL libusb_reset_device(libusb_device_handle *dev_handle) {
    (void)dev_handle;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int LIBUSB_CALL libusb_control_transfer(
    libusb_device_handle *dev_handle,
    uint8_t bmRequestType,
    uint8_t bRequest,
    uint16_t wValue,
    uint16_t wIndex,
    unsigned char *data,
    uint16_t wLength,
    unsigned int timeout
) {
    (void)dev_handle;
    (void)bmRequestType;
    (void)bRequest;
    (void)wValue;
    (void)wIndex;
    (void)data;
    (void)wLength;
    (void)timeout;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

struct libusb_transfer *LIBUSB_CALL libusb_alloc_transfer(int iso_packets) {
    (void)iso_packets;
    return NULL;
}

void LIBUSB_CALL libusb_free_transfer(struct libusb_transfer *transfer) {
    free(transfer);
}

int LIBUSB_CALL libusb_submit_transfer(struct libusb_transfer *transfer) {
    (void)transfer;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int LIBUSB_CALL libusb_cancel_transfer(struct libusb_transfer *transfer) {
    (void)transfer;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int LIBUSB_CALL libusb_handle_events_timeout_completed(libusb_context *ctx, struct timeval *tv, int *completed) {
    (void)ctx;
    (void)tv;
    (void)completed;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int LIBUSB_CALL libusb_handle_events_completed(libusb_context *ctx, int *completed) {
    (void)ctx;
    (void)completed;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int LIBUSB_CALL libusb_android_set_raw_descriptors(libusb_device_handle *dev_handle, const uint8_t *raw_desc, size_t len) {
    (void)dev_handle;
    (void)raw_desc;
    (void)len;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

const uint8_t *LIBUSB_CALL libusb_android_get_raw_descriptors(libusb_device_handle *dev_handle, size_t *out_len) {
    (void)dev_handle;
    if (out_len) *out_len = 0;
    return NULL;
}

#endif

const char *LIBUSB_CALL libusb_error_name(int errcode) {
    switch (errcode) {
    case LIBUSB_SUCCESS:
        return "LIBUSB_SUCCESS";
    case LIBUSB_ERROR_IO:
        return "LIBUSB_ERROR_IO";
    case LIBUSB_ERROR_INVALID_PARAM:
        return "LIBUSB_ERROR_INVALID_PARAM";
    case LIBUSB_ERROR_ACCESS:
        return "LIBUSB_ERROR_ACCESS";
    case LIBUSB_ERROR_NO_DEVICE:
        return "LIBUSB_ERROR_NO_DEVICE";
    case LIBUSB_ERROR_NOT_FOUND:
        return "LIBUSB_ERROR_NOT_FOUND";
    case LIBUSB_ERROR_BUSY:
        return "LIBUSB_ERROR_BUSY";
    case LIBUSB_ERROR_TIMEOUT:
        return "LIBUSB_ERROR_TIMEOUT";
    case LIBUSB_ERROR_OVERFLOW:
        return "LIBUSB_ERROR_OVERFLOW";
    case LIBUSB_ERROR_PIPE:
        return "LIBUSB_ERROR_PIPE";
    case LIBUSB_ERROR_INTERRUPTED:
        return "LIBUSB_ERROR_INTERRUPTED";
    case LIBUSB_ERROR_NO_MEM:
        return "LIBUSB_ERROR_NO_MEM";
    case LIBUSB_ERROR_NOT_SUPPORTED:
        return "LIBUSB_ERROR_NOT_SUPPORTED";
    default:
        return "LIBUSB_ERROR_OTHER";
    }
}
