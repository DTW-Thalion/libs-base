/** Zone memory management. -*- Mode: ObjC -*-
   Copyright (C) 1997,1998 Free Software Foundation, Inc.

   Written by: Yoo C. Chung <wacko@laplace.snu.ac.kr>
   Date: January 1997
   Rewrite by: Richard Frith-Macdonald <richard@brainstrom.co.uk>
   2026 rewrite (Option A shim): per spike
   docs/spikes/2026-04-13-nszone-removal.md in the gnustep-audit tree.
   The segregated-fit freeable-zone allocator and the worst-fit
   nonfreeable-zone allocator have been removed; every public NSZone
   API now forwards directly to the system malloc family. See the
   spike doc for rationale, ABI analysis (zero symbol removals, zero
   SOVERSION bump) and the audit that confirmed no downstream
   consumer reaches into struct _NSZone.

   This file is part of the GNUstep Base Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public License
   as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful, but
   WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free Software
   Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.

   <title>NSZone class reference</title>
   $Date$ $Revision$
*/

#define IN_NSZONE_M 1

#import "common.h"
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#import "Foundation/NSException.h"
#import "Foundation/NSLock.h"
#import "GSPrivate.h"
#import "GSPThread.h"

/*
 * struct _NSZone is opaque in Foundation/NSZone.h (line 32):
 *
 *     typedef struct _NSZone NSZone;
 *
 * No public header exposes the layout, and an audit across libs-gui,
 * libs-back, libs-corebase, libs-opal and libs-quartzcore (see spike
 * §3) found zero downstream struct-field accesses.  The fields below
 * are therefore internal-only and exist solely to store an optional
 * debug name for NSSetZoneName / NSZoneName.
 */
struct _NSZone
{
  __unsafe_unretained NSString *name;
};

/*
 * The one-and-only sentinel zone.  Every NSZone* returned by any
 * API in this file is a pointer to this single static instance.
 *
 * NSDefaultMallocZone(), NSCreateZone(), NSZoneFromPointer() and
 * GSAtomicMallocZone() all return &default_zone.  NSRecycleZone is a
 * no-op.  This makes zone-identity comparisons (zone1 == zone2) still
 * well-defined: every zone is the same zone.
 */
static struct _NSZone default_zone = { nil };

/*
 * Exported for backward compatibility with anything that historically
 * linked against this symbol (it has always been part of the .so even
 * though no public header declares it).  Preserved to avoid a symbol
 * removal.
 */
NSZone	*__nszone_private_hidden_default_zone = &default_zone;

/* Lock protecting default_zone.name mutation. */
static gs_mutex_t  zoneLock = GS_MUTEX_INIT_STATIC;


/**
 * Try to get more memory - the normal process has failed.
 * If we can't do anything, just return a null pointer.
 * Try to do some logging if possible.
 */
void *
GSOutOfMemory(NSUInteger size, BOOL retry)
{
  fprintf(stderr, "GSOutOfMemory ... wanting %"PRIuPTR" bytes.\n", size);
  return 0;
}


GS_DECLARE NSZone*
NSDefaultMallocZone (void)
{
  return &default_zone;
}

NSZone*
GSAtomicMallocZone (void)
{
  return &default_zone;
}

GS_DECLARE NSZone*
NSCreateZone (NSUInteger start, NSUInteger gran, BOOL canFree)
{
  /*
   * Option A: pretend to create a zone.  All allocations go through
   * the system malloc regardless, so returning the sentinel is
   * correct and keeps every "if (zone != NULL)" caller happy.
   */
  (void)start;
  (void)gran;
  (void)canFree;
  return &default_zone;
}

GS_DECLARE void
NSRecycleZone (NSZone *zone)
{
  /*
   * No-op.  The sentinel is permanent and memory allocated through
   * NSZoneMalloc went straight to the system allocator — there is
   * no per-zone arena to reclaim.  This matches Apple Foundation
   * behavior since macOS 10.6+.
   */
  (void)zone;
}

GS_DECLARE NSZone*
NSZoneFromPointer(void *ptr)
{
  if (ptr == 0) return 0;
  return &default_zone;
}

GS_DECLARE void*
NSZoneMalloc (NSZone *zone, NSUInteger size)
{
  (void)zone;
  return malloc(size);
}

GS_DECLARE void*
NSZoneCalloc (NSZone *zone, NSUInteger elems, NSUInteger bytes)
{
  (void)zone;
  return calloc(elems, bytes);
}

GS_DECLARE void*
NSZoneRealloc (NSZone *zone, void *ptr, NSUInteger size)
{
  (void)zone;
  return realloc(ptr, size);
}

GS_DECLARE void
NSZoneFree (NSZone *zone, void *ptr)
{
  (void)zone;
  free(ptr);
}

GS_DECLARE void
NSSetZoneName (NSZone *zone, NSString *name)
{
  if (!zone)
    zone = NSDefaultMallocZone();
  GS_MUTEX_LOCK(zoneLock);
  name = [name copy];
  if (zone->name != nil)
    [zone->name release];
  zone->name = name;
  GS_MUTEX_UNLOCK(zoneLock);
}

GS_DECLARE NSString*
NSZoneName (NSZone *zone)
{
  if (!zone)
    zone = NSDefaultMallocZone();
  return zone->name;
}

BOOL
NSZoneCheck (NSZone *zone)
{
  (void)zone;
  return YES;
}

struct NSZoneStats
NSZoneStats (NSZone *zone)
{
  struct NSZoneStats stats;
  (void)zone;
  memset(&stats, 0, sizeof(stats));
  return stats;
}

GS_DECLARE void*
NSAllocateCollectable(NSUInteger size, NSUInteger options)
{
  (void)options;
  return calloc(1, size);
}

GS_DECLARE void*
NSReallocateCollectable(void *ptr, NSUInteger size, NSUInteger options)
{
  (void)options;
  return realloc(ptr, size);
}

BOOL
GSPrivateIsCollectable(const void *ptr)
{
  (void)ptr;
  return NO;
}
