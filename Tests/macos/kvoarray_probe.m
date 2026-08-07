/* What Apple's Foundation does for a key path that passes through an array.
 *
 * libs-base #707: registering such a key path observes nothing on GNUstep.
 * Registration on an array itself is documented to raise.  What is not
 * documented is what happens when the array is reached through another
 * object, which is the case in the issue, and whether the aggregate operators
 * and the ordered to-many helpers keep working.
 *
 * Each case runs in its own process, because a raise may leave the observation
 * state of the process altered.
 */
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>

@interface      Element : NSObject
@property (copy) NSString *name;
@end
@implementation Element
@end

@interface      Holder : NSObject
{
  NSMutableArray	*_helpers;
}
@property (retain) NSArray *plain;
@end

@implementation Holder
- (instancetype) init
{
  if (nil != (self = [super init]))
    {
      _helpers = [NSMutableArray new];
    }
  return self;
}
/* An ordered to-many property reached through the KVC accessors, which is
 * what makes a change to the collection itself observable. */
- (NSUInteger) countOfHelpers
{
  return [_helpers count];
}
- (id) objectInHelpersAtIndex: (NSUInteger)i
{
  return [_helpers objectAtIndex: i];
}
- (void) insertObject: (id)o inHelpersAtIndex: (NSUInteger)i
{
  [_helpers insertObject: o atIndex: i];
}
- (void) removeObjectFromHelpersAtIndex: (NSUInteger)i
{
  [_helpers removeObjectAtIndex: i];
}
@end

@interface      Obs : NSObject
{
@public
  int		 count;
  NSString	*lastKeyPath;
  id		 lastObject;
}
@end

@implementation Obs
- (void) observeValueForKeyPath: (NSString *)keyPath
                       ofObject: (id)object
                         change: (NSDictionary *)change
                        context: (void *)context
{
  count++;
  lastKeyPath = [keyPath copy];
  lastObject = object;
}
@end

static int
reg(id target, NSString *keypath, Obs *obs)
{
  @try
    {
      [target addObserver: obs
               forKeyPath: keypath
                  options: NSKeyValueObservingOptionNew
                  context: NULL];
      printf("  register %-28s ok\n", [keypath UTF8String]);
      return 1;
    }
  @catch (NSException *e)
    {
      printf("  register %-28s RAISED %s: %s\n", [keypath UTF8String],
        [[e name] UTF8String], [[e reason] UTF8String]);
      return 0;
    }
}

static void
unreg(id target, NSString *keypath, Obs *obs)
{
  @try
    {
      [target removeObserver: obs forKeyPath: keypath];
      printf("  remove   %-28s ok\n", [keypath UTF8String]);
    }
  @catch (NSException *e)
    {
      printf("  remove   %-28s RAISED %s\n", [keypath UTF8String],
        [[e name] UTF8String]);
    }
}

static void
report(Obs *obs, const char *what)
{
  printf("  %-38s notifications=%d keyPath=%s object=%s\n", what, obs->count,
    obs->lastKeyPath ? [obs->lastKeyPath UTF8String] : "(none)",
    obs->lastObject ? [NSStringFromClass([obs->lastObject class]) UTF8String]
                    : "(none)");
}

int
main(int argc, char **argv)
{
  NSAutoreleasePool	*arp = [NSAutoreleasePool new];
  const char		*mode = (argc > 1) ? argv[1] : "";
  Obs			*obs = [Obs new];

  if (0 == strcmp(mode, "1-direct-on-array"))
    {
      NSArray *a = [NSArray arrayWithObject: [Element new]];

      if (reg(a, @"name", obs)) unreg(a, @"name", obs);
    }
  else if (0 == strcmp(mode, "2-through-dictionary"))
    {
      /* The reproduction on the issue. */
      Element		  *e = [Element new];
      NSMutableDictionary *d = [NSMutableDictionary dictionary];

      [e setName: @"a"];
      [d setObject: [NSArray arrayWithObject: e] forKey: @"list"];
      if (reg(d, @"list.name", obs))
        {
          [e setName: @"b"];
          report(obs, "after changing an element's name");
          [d setObject: [NSArray arrayWithObject: [Element new]]
                forKey: @"list"];
          report(obs, "after replacing the whole array");
          unreg(d, @"list.name", obs);
        }
    }
  else if (0 == strcmp(mode, "3-plain-array-property"))
    {
      Holder  *h = [Holder new];
      Element *e = [Element new];

      [e setName: @"a"];
      [h setPlain: [NSArray arrayWithObject: e]];
      if (reg(h, @"plain.name", obs))
        {
          [e setName: @"b"];
          report(obs, "after changing an element's name");
          [h setPlain: [NSArray arrayWithObject: [Element new]]];
          report(obs, "after replacing the array property");
          unreg(h, @"plain.name", obs);
        }
    }
  else if (0 == strcmp(mode, "4-ordered-to-many"))
    {
      /* The case Tests/base/NSKVOSupport/kvoToMany.m asserts one
       * notification for. */
      Holder *h = [Holder new];

      [h insertObject: [Element new] inHelpersAtIndex: 0];
      if (reg(h, @"helpers.name", obs))
        {
          [h insertObject: [Element new] inHelpersAtIndex: 0];
          report(obs, "after inserting into the to-many property");
          [[h objectInHelpersAtIndex: 0] setName: @"z"];
          report(obs, "after changing an element's name");
          unreg(h, @"helpers.name", obs);
        }
    }
  else if (0 == strcmp(mode, "5-operator-count"))
    {
      Holder *h = [Holder new];

      [h insertObject: [Element new] inHelpersAtIndex: 0];
      if (reg(h, @"helpers.@count", obs))
        {
          [h insertObject: [Element new] inHelpersAtIndex: 0];
          report(obs, "after inserting into the to-many property");
          unreg(h, @"helpers.@count", obs);
        }
    }
  else if (0 == strcmp(mode, "6-direct-on-set"))
    {
      NSSet *s = [NSSet setWithObject: [Element new]];

      if (reg(s, @"name", obs)) unreg(s, @"name", obs);
    }
  else if (0 == strcmp(mode, "7-nested-deeper"))
    {
      /* Two keys after the array, to see whether the whole tail is refused
       * or only the key immediately after it. */
      Element		  *e = [Element new];
      NSMutableDictionary *d = [NSMutableDictionary dictionary];

      [e setName: @"a"];
      [d setObject: [NSArray arrayWithObject: e] forKey: @"list"];
      if (reg(d, @"list.name.length", obs))
        {
          [e setName: @"bb"];
          report(obs, "after changing an element's name");
          unreg(d, @"list.name.length", obs);
        }
    }
  else
    {
      printf("unknown mode\n");
    }

  [arp release];
  return 0;
}
