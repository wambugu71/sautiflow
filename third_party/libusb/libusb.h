#ifndef SAUTIFLOW_LIBUSB_H
#define SAUTIFLOW_LIBUSB_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define SAUTIFLOW_LIBUSB_DEFINED_LEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#ifdef SAUTIFLOW_LIBUSB_DEFINED_LEAN
#undef WIN32_LEAN_AND_MEAN
#undef SAUTIFLOW_LIBUSB_DEFINED_LEAN
#endif
#else
#include <sys/time.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

#ifndef LIBUSB_CALL
#define LIBUSB_CALL
#endif

typedef struct libusb_context libusb_context;
typedef struct libusb_device libusb_device;
typedef struct libusb_device_handle libusb_device_handle;

enum libusb_class_code {
    LIBUSB_CLASS_PER_INTERFACE = 0,
    LIBUSB_CLASS_AUDIO = 1,
    LIBUSB_CLASS_COMM = 2,
    LIBUSB_CLASS_HID = 3,
    LIBUSB_CLASS_PHYSICAL = 5,
    LIBUSB_CLASS_IMAGE = 6,
    LIBUSB_CLASS_PRINTER = 7,
    LIBUSB_CLASS_MASS_STORAGE = 8,
    LIBUSB_CLASS_HUB = 9,
    LIBUSB_CLASS_DATA = 10,
    LIBUSB_CLASS_VENDOR_SPEC = 0xff
};

enum libusb_descriptor_type {
    LIBUSB_DT_DEVICE = 0x01,
    LIBUSB_DT_CONFIG = 0x02,
    LIBUSB_DT_STRING = 0x03,
    LIBUSB_DT_INTERFACE = 0x04,
    LIBUSB_DT_ENDPOINT = 0x05,
    LIBUSB_DT_INTERFACE_ASSOCIATION = 0x0b,
    LIBUSB_DT_CS_INTERFACE = 0x24,
    LIBUSB_DT_CS_ENDPOINT = 0x25
};

enum libusb_endpoint_direction {
    LIBUSB_ENDPOINT_OUT = 0x00,
    LIBUSB_ENDPOINT_IN = 0x80
};

enum libusb_transfer_type {
    LIBUSB_TRANSFER_TYPE_CONTROL = 0,
    LIBUSB_TRANSFER_TYPE_ISOCHRONOUS = 1,
    LIBUSB_TRANSFER_TYPE_BULK = 2,
    LIBUSB_TRANSFER_TYPE_INTERRUPT = 3,
    LIBUSB_TRANSFER_TYPE_BULK_STREAM = 4
};

enum libusb_request_type {
    LIBUSB_REQUEST_TYPE_STANDARD = (0x00 << 5),
    LIBUSB_REQUEST_TYPE_CLASS = (0x01 << 5),
    LIBUSB_REQUEST_TYPE_VENDOR = (0x02 << 5),
    LIBUSB_REQUEST_TYPE_RESERVED = (0x03 << 5)
};

enum libusb_request_recipient {
    LIBUSB_RECIPIENT_DEVICE = 0x00,
    LIBUSB_RECIPIENT_INTERFACE = 0x01,
    LIBUSB_RECIPIENT_ENDPOINT = 0x02,
    LIBUSB_RECIPIENT_OTHER = 0x03
};

enum libusb_speed {
    LIBUSB_SPEED_UNKNOWN = 0,
    LIBUSB_SPEED_LOW = 1,
    LIBUSB_SPEED_FULL = 2,
    LIBUSB_SPEED_HIGH = 3,
    LIBUSB_SPEED_SUPER = 4,
    LIBUSB_SPEED_SUPER_PLUS = 5
};

enum libusb_error {
    LIBUSB_SUCCESS = 0,
    LIBUSB_ERROR_IO = -1,
    LIBUSB_ERROR_INVALID_PARAM = -2,
    LIBUSB_ERROR_ACCESS = -3,
    LIBUSB_ERROR_NO_DEVICE = -4,
    LIBUSB_ERROR_NOT_FOUND = -5,
    LIBUSB_ERROR_BUSY = -6,
    LIBUSB_ERROR_TIMEOUT = -7,
    LIBUSB_ERROR_OVERFLOW = -8,
    LIBUSB_ERROR_PIPE = -9,
    LIBUSB_ERROR_INTERRUPTED = -10,
    LIBUSB_ERROR_NO_MEM = -11,
    LIBUSB_ERROR_NOT_SUPPORTED = -12,
    LIBUSB_ERROR_OTHER = -99
};

enum libusb_transfer_status {
    LIBUSB_TRANSFER_COMPLETED = 0,
    LIBUSB_TRANSFER_ERROR = 1,
    LIBUSB_TRANSFER_TIMED_OUT = 2,
    LIBUSB_TRANSFER_CANCELLED = 3,
    LIBUSB_TRANSFER_STALL = 4,
    LIBUSB_TRANSFER_NO_DEVICE = 5,
    LIBUSB_TRANSFER_OVERFLOW = 6
};

enum libusb_option {
    LIBUSB_OPTION_LOG_LEVEL = 0,
    LIBUSB_OPTION_USE_USBDK = 1,
    LIBUSB_OPTION_NO_DEVICE_DISCOVERY = 2
};

struct libusb_device_descriptor {
    uint8_t bLength;
    uint8_t bDescriptorType;
    uint16_t bcdUSB;
    uint8_t bDeviceClass;
    uint8_t bDeviceSubClass;
    uint8_t bDeviceProtocol;
    uint8_t bMaxPacketSize0;
    uint16_t idVendor;
    uint16_t idProduct;
    uint16_t bcdDevice;
    uint8_t iManufacturer;
    uint8_t iProduct;
    uint8_t iSerialNumber;
    uint8_t bNumConfigurations;
};

struct libusb_endpoint_descriptor {
    uint8_t bLength;
    uint8_t bDescriptorType;
    uint8_t bEndpointAddress;
    uint8_t bmAttributes;
    uint16_t wMaxPacketSize;
    uint8_t bInterval;
    uint8_t bRefresh;
    uint8_t bSynchAddress;
    const unsigned char *extra;
    int extra_length;
};

struct libusb_interface_descriptor {
    uint8_t bLength;
    uint8_t bDescriptorType;
    uint8_t bInterfaceNumber;
    uint8_t bAlternateSetting;
    uint8_t bNumEndpoints;
    uint8_t bInterfaceClass;
    uint8_t bInterfaceSubClass;
    uint8_t bInterfaceProtocol;
    uint8_t iInterface;
    const struct libusb_endpoint_descriptor *endpoint;
    const unsigned char *extra;
    int extra_length;
};

struct libusb_interface {
    const struct libusb_interface_descriptor *altsetting;
    int num_altsetting;
};

#if defined(_WIN32) && defined(interface)
#pragma push_macro("interface")
#undef interface
#define SAUTIFLOW_LIBUSB_POP_INTERFACE
#endif
struct libusb_config_descriptor {
    uint8_t bLength;
    uint8_t bDescriptorType;
    uint16_t wTotalLength;
    uint8_t bNumInterfaces;
    uint8_t bConfigurationValue;
    uint8_t iConfiguration;
    uint8_t bmAttributes;
    uint8_t MaxPower;
    const struct libusb_interface *interface;
    const unsigned char *extra;
    int extra_length;
};
#ifdef SAUTIFLOW_LIBUSB_POP_INTERFACE
#pragma pop_macro("interface")
#undef SAUTIFLOW_LIBUSB_POP_INTERFACE
#endif

struct libusb_iso_packet_descriptor {
    unsigned int length;
    unsigned int actual_length;
    enum libusb_transfer_status status;
};

struct libusb_transfer;
typedef void (LIBUSB_CALL *libusb_transfer_cb_fn)(struct libusb_transfer *transfer);

struct libusb_transfer {
    libusb_device_handle *dev_handle;
    uint8_t flags;
    unsigned char endpoint;
    unsigned char type;
    unsigned int timeout;
    enum libusb_transfer_status status;
    int length;
    int actual_length;
    libusb_transfer_cb_fn callback;
    void *user_data;
    unsigned char *buffer;
    int num_iso_packets;
    struct libusb_iso_packet_descriptor iso_packet_desc[1];
};

int LIBUSB_CALL libusb_init(libusb_context **ctx);
void LIBUSB_CALL libusb_exit(libusb_context *ctx);
int LIBUSB_CALL libusb_set_option(libusb_context *ctx, enum libusb_option option, ...);

int LIBUSB_CALL libusb_wrap_sys_device(libusb_context *ctx, intptr_t sys_dev, libusb_device_handle **dev_handle);
void LIBUSB_CALL libusb_close(libusb_device_handle *dev_handle);
libusb_device *LIBUSB_CALL libusb_get_device(libusb_device_handle *dev_handle);
int LIBUSB_CALL libusb_get_device_speed(libusb_device *dev);

int LIBUSB_CALL libusb_get_device_descriptor(libusb_device *dev, struct libusb_device_descriptor *desc);
int LIBUSB_CALL libusb_get_active_config_descriptor(libusb_device *dev, struct libusb_config_descriptor **config);
void LIBUSB_CALL libusb_free_config_descriptor(struct libusb_config_descriptor *config);

int LIBUSB_CALL libusb_set_auto_detach_kernel_driver(libusb_device_handle *dev_handle, int enable);
int LIBUSB_CALL libusb_kernel_driver_active(libusb_device_handle *dev_handle, int interface_number);
int LIBUSB_CALL libusb_detach_kernel_driver(libusb_device_handle *dev_handle, int interface_number);
int LIBUSB_CALL libusb_attach_kernel_driver(libusb_device_handle *dev_handle, int interface_number);

int LIBUSB_CALL libusb_claim_interface(libusb_device_handle *dev_handle, int interface_number);
int LIBUSB_CALL libusb_release_interface(libusb_device_handle *dev_handle, int interface_number);
int LIBUSB_CALL libusb_set_interface_alt_setting(libusb_device_handle *dev_handle, int interface_number, int alternate_setting);
int LIBUSB_CALL libusb_clear_halt(libusb_device_handle *dev_handle, unsigned char endpoint);
int LIBUSB_CALL libusb_reset_device(libusb_device_handle *dev_handle);

int LIBUSB_CALL libusb_control_transfer(
    libusb_device_handle *dev_handle,
    uint8_t bmRequestType,
    uint8_t bRequest,
    uint16_t wValue,
    uint16_t wIndex,
    unsigned char *data,
    uint16_t wLength,
    unsigned int timeout
);

struct libusb_transfer *LIBUSB_CALL libusb_alloc_transfer(int iso_packets);
void LIBUSB_CALL libusb_free_transfer(struct libusb_transfer *transfer);
int LIBUSB_CALL libusb_submit_transfer(struct libusb_transfer *transfer);
int LIBUSB_CALL libusb_cancel_transfer(struct libusb_transfer *transfer);

int LIBUSB_CALL libusb_handle_events_timeout_completed(libusb_context *ctx, struct timeval *tv, int *completed);
int LIBUSB_CALL libusb_handle_events_completed(libusb_context *ctx, int *completed);
const char *LIBUSB_CALL libusb_error_name(int errcode);

/* Android helper: seed raw descriptors (from UsbDeviceConnection.getRawDescriptors)
 * when usbfs fd read() is restricted or incomplete. */
int LIBUSB_CALL libusb_android_set_raw_descriptors(libusb_device_handle *dev_handle, const uint8_t *raw_desc, size_t len);
const uint8_t *LIBUSB_CALL libusb_android_get_raw_descriptors(libusb_device_handle *dev_handle, size_t *out_len);

static inline void libusb_fill_iso_transfer(
    struct libusb_transfer *transfer,
    libusb_device_handle *dev_handle,
    unsigned char endpoint,
    unsigned char *buffer,
    int length,
    int num_iso_packets,
    libusb_transfer_cb_fn callback,
    void *user_data,
    unsigned int timeout
) {
    transfer->dev_handle = dev_handle;
    transfer->endpoint = endpoint;
    transfer->type = LIBUSB_TRANSFER_TYPE_ISOCHRONOUS;
    transfer->timeout = timeout;
    transfer->buffer = buffer;
    transfer->length = length;
    transfer->num_iso_packets = num_iso_packets;
    transfer->user_data = user_data;
    transfer->callback = callback;
}

static inline void libusb_set_iso_packet_lengths(struct libusb_transfer *transfer, unsigned int length) {
    int i;
    for (i = 0; i < transfer->num_iso_packets; ++i) {
        transfer->iso_packet_desc[i].length = length;
    }
}

static inline unsigned char *libusb_get_iso_packet_buffer_simple(struct libusb_transfer *transfer, unsigned int packet) {
    if (!transfer || !transfer->buffer || packet >= (unsigned int)transfer->num_iso_packets) {
        return NULL;
    }
    if (packet == 0) {
        return transfer->buffer;
    }
    unsigned int offset = 0;
    for (unsigned int i = 0; i < packet; ++i) {
        offset += transfer->iso_packet_desc[i].length;
    }
    return transfer->buffer + offset;
}

#ifdef __cplusplus
}
#endif

#endif /* SAUTIFLOW_LIBUSB_H */
