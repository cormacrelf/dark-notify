#ifndef host_h
#define host_h

#include <stdint.h>
#include <Foundation/Foundation.h>

typedef NS_ENUM(uint32_t, Appearance) {
    AppearanceLight,
    AppearanceDark,
};
typedef struct opaque opaque;
void call_boxed_callback(opaque * callback, enum Appearance appearance);

#endif /* host_h */
