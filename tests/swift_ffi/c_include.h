// Any copyright is dedicated to the Public Domain.
// https://creativecommons.org/publicdomain/zero/1.0/

#ifndef __C_INCLUDE_H__
#define __C_INCLUDE_H__

// if interop-cxx has enabled
#if defined(__cplusplus)
extern "C" {
#endif

void println(char const *);

#if defined(__cplusplus)
}
#endif
#endif //__C_INCLUDE_H__