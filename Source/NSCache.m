/** Implementation for NSCache for GNUStep
   Copyright (C) 2009 Free Software Foundation, Inc.

   Written by:  David Chisnall <csdavec@swan.ac.uk>
   Created: 2009

   This file is part of the GNUstep Base Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
   */

#import "common.h"

#define	EXPOSE_NSCache_IVARS	1

#import "Foundation/NSArray.h"
#import "Foundation/NSCache.h"
#import "Foundation/NSMapTable.h"
#import "Foundation/NSEnumerator.h"
#import "Foundation/NSLock.h"

/**
 * _GSCachedObject is effectively used as a structure containing the various
 * things that need to be associated with objects stored in an NSCache.  It is
 * an NSObject subclass so that it can be used with OpenStep collection
 * classes.
 *
 * Contains intrusive doubly-linked list pointers for O(1) LRU operations.
 */
@interface _GSCachedObject : NSObject
{
  @public
  id object;
  NSString *key;
  int accessCount;
  NSUInteger cost;
  BOOL isEvictable;
  _GSCachedObject *_lruNext;
  _GSCachedObject *_lruPrev;
}
@end

@interface NSCache (EvictionPolicy)
/** The method controlling eviction policy in an NSCache. */
- (void) _evictObjectsToMakeSpaceForObjectWithCost: (NSUInteger)cost;
@end

/**
 * Intrusive doubly-linked list providing O(1) LRU operations.
 * Tail is most-recently-used, head is least-recently-used.
 */
typedef struct {
  _GSCachedObject *head;
  _GSCachedObject *tail;
} _GSLRUList;

static inline void _lruRemove(_GSLRUList *list, _GSCachedObject *obj)
{
  if (obj->_lruPrev)
    obj->_lruPrev->_lruNext = obj->_lruNext;
  else
    list->head = obj->_lruNext;

  if (obj->_lruNext)
    obj->_lruNext->_lruPrev = obj->_lruPrev;
  else
    list->tail = obj->_lruPrev;

  obj->_lruNext = nil;
  obj->_lruPrev = nil;
}

static inline void _lruAppend(_GSLRUList *list, _GSCachedObject *obj)
{
  obj->_lruPrev = list->tail;
  obj->_lruNext = nil;
  if (list->tail)
    list->tail->_lruNext = obj;
  else
    list->head = obj;
  list->tail = obj;
}

static inline void _lruMoveToTail(_GSLRUList *list, _GSCachedObject *obj)
{
  if (obj == list->tail)
    return;
  _lruRemove(list, obj);
  _lruAppend(list, obj);
}

@implementation NSCache
- (id) init
{
  if (nil == (self = [super init]))
    {
      return nil;
    }
  ASSIGN(_objects, [NSMapTable strongToStrongObjectsMapTable]);
  /* Repurpose _accesses to hold a heap-allocated _GSLRUList struct.
   * We store it as an NSValue wrapping the pointer. */
  {
    _GSLRUList *lru = calloc(1, sizeof(_GSLRUList));
    _accesses = (id)lru;
  }
  _lock = [NSRecursiveLock new];
  return self;
}

- (NSUInteger) countLimit
{
  return _countLimit;
}

- (id) delegate
{
  return _delegate;
}

- (BOOL) evictsObjectsWithDiscardedContent
{
  return _evictsObjectsWithDiscardedContent;
}

- (NSString*) name
{
  NSString	*n;

  [_lock lock];
  n = RETAIN(_name);
  [_lock unlock];
  return AUTORELEASE(n);
}

- (id) objectForKey: (id)key
{
  _GSCachedObject	*obj;
  id			value;

  [_lock lock];
  obj = [_objects objectForKey: key];
  if (nil == obj)
    {
      [_lock unlock];
      return nil;
    }
  if (obj->isEvictable)
    {
      // O(1) move to most-recently-used position
      _lruMoveToTail((_GSLRUList *)_accesses, obj);
    }
  obj->accessCount++;
  _totalAccesses++;
  value = RETAIN(obj->object);
  [_lock unlock];
  return AUTORELEASE(value);
}

- (void) removeAllObjects
{
  NSEnumerator		*e;
  _GSCachedObject	*obj;

  [_lock lock];
  e = [_objects objectEnumerator];
  while (nil != (obj = [e nextObject]))
    {
      [_delegate cache: self willEvictObject: obj->object];
    }
  [_objects removeAllObjects];
  {
    _GSLRUList *lru = (_GSLRUList *)_accesses;
    lru->head = nil;
    lru->tail = nil;
  }
  _totalAccesses = 0;
  [_lock unlock];
}

- (void) removeObjectForKey: (id)key
{
  _GSCachedObject	*obj;

  [_lock lock];
  obj = [_objects objectForKey: key];
  if (nil != obj)
    {
      [_delegate cache: self willEvictObject: obj->object];
      _totalAccesses -= obj->accessCount;
      if (obj->isEvictable)
        {
          _lruRemove((_GSLRUList *)_accesses, obj);
        }
      [_objects removeObjectForKey: key];
    }
  [_lock unlock];
}

- (void) setCountLimit: (NSUInteger)lim
{
  _countLimit = lim;
}

- (void) setDelegate:(id)del
{
  _delegate = del;
}

- (void) setEvictsObjectsWithDiscardedContent:(BOOL)b
{
  _evictsObjectsWithDiscardedContent = b;
}

- (void) setName: (NSString*)cacheName
{
  [_lock lock];
  ASSIGN(_name, cacheName);
  [_lock unlock];
}

- (void) setObject: (id)obj forKey: (id)key cost: (NSUInteger)num
{
  _GSCachedObject *oldObject;
  _GSCachedObject *newObject;

  [_lock lock];
  oldObject = [_objects objectForKey: key];
  if (nil != oldObject)
    {
      [self removeObjectForKey: oldObject->key];
    }
  [self _evictObjectsToMakeSpaceForObjectWithCost: num];
  newObject = [_GSCachedObject new];
  // Retained here, released when obj is dealloc'd
  newObject->object = RETAIN(obj);
  newObject->key = RETAIN(key);
  newObject->cost = num;
  // All objects participate in LRU eviction, not just NSDiscardableContent
  newObject->isEvictable = YES;
  _lruAppend((_GSLRUList *)_accesses, newObject);
  [_objects setObject: newObject forKey: key];
  RELEASE(newObject);
  _totalCost += num;
  [_lock unlock];
}

- (void) setObject: (id)obj forKey: (id)key
{
  [self setObject: obj forKey: key cost: 0];
}

- (void) setTotalCostLimit: (NSUInteger)lim
{
  _costLimit = lim;
}

- (NSUInteger) totalCostLimit
{
  return _costLimit;
}

/**
 * This method handles the eviction policy.  Objects are evicted from the
 * LRU head (least recently used) first.  NSDiscardableContent objects have
 * their content discarded; all other objects are removed directly when
 * eviction is needed.
 */
- (void) _evictObjectsToMakeSpaceForObjectWithCost: (NSUInteger)cost
{
  NSUInteger spaceNeeded = 0;
  NSUInteger count;

  [_lock lock];
  count = [_objects count];
  if (_costLimit > 0 && _totalCost + cost > _costLimit)
    {
      spaceNeeded = _totalCost + cost - _costLimit;
    }

  // Only evict if we need the space.
  if (count > 0 && (spaceNeeded > 0 || count >= _countLimit))
    {
      _GSLRUList *lru = (_GSLRUList *)_accesses;
      _GSCachedObject *obj = lru->head;
      NSUInteger averageAccesses = ((_totalAccesses / (double)count) * 0.2) + 1;
      NSMutableArray *evictedKeys = [[NSMutableArray alloc] init];

      while (nil != obj)
	{
	  _GSCachedObject *next = obj->_lruNext;

	  // Don't evict frequently accessed objects.
	  if (obj->accessCount < averageAccesses)
	    {
	      if ([obj->object conformsToProtocol: @protocol(NSDiscardableContent)])
	        {
	          [obj->object discardContentIfPossible];
	          if ([obj->object isContentDiscarded])
		    {
		      [evictedKeys addObject: obj->key];
		      _totalCost -= obj->cost;
		      obj->cost = 0;
		      obj->isEvictable = NO;
		      if (obj->cost > spaceNeeded)
		        {
		          spaceNeeded = 0;
		        }
		      else
		        {
		          spaceNeeded -= obj->cost;
		        }
		    }
	        }
	      else
	        {
	          // Evict non-discardable objects directly
	          [evictedKeys addObject: obj->key];
	          if (obj->cost >= spaceNeeded)
	            {
	              spaceNeeded = 0;
	            }
	          else
	            {
	              spaceNeeded -= obj->cost;
	            }
	        }
	    }

	  // If we've freed enough space, stop
	  if (spaceNeeded == 0 && count - [evictedKeys count] < _countLimit)
	    {
	      break;
	    }
	  obj = next;
	}
      // Remove all evicted objects
      {
	NSString *key;
	NSEnumerator *e = [evictedKeys objectEnumerator];
	while (nil != (key = [e nextObject]))
	  {
	    [self removeObjectForKey: key];
	  }
      }
      RELEASE(evictedKeys);
    }
  [_lock unlock];
}

- (void) dealloc
{
  RELEASE(_lock);
  RELEASE(_name);
  RELEASE(_objects);
  free((_GSLRUList *)_accesses);
  DEALLOC
}
@end

@implementation _GSCachedObject
- (void) dealloc
{
  RELEASE(object);
  RELEASE(key);
  DEALLOC
}
@end
