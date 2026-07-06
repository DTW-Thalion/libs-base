/* NSSecureCoding behavior oracle. Compile against Apple Foundation on macOS:
 *   clang -framework Foundation securecoding_oracle.m -o oracle && ./oracle
 * Also compiles/runs under GNUstep for A/B comparison. Prints Apple's actual
 * behavior for each ambiguous secure-coding scenario so the GNUstep
 * implementation can match it exactly.
 */
#import <Foundation/Foundation.h>

static const char *R(id obj, NSError *err)
{
  static char buf[512];
  snprintf(buf, sizeof(buf), "obj=%s  err=%s",
    obj ? [[obj description] UTF8String] : "(nil)",
    err ? [[NSString stringWithFormat: @"%@ / %@",
             [err domain], [[err userInfo] objectForKey: NSLocalizedDescriptionKey]] UTF8String]
        : "(nil)");
  return buf;
}

/* Archive helper (secure). */
static NSData *arch(id root)
{
  NSError *e = nil;
  NSData *d = [NSKeyedArchiver archivedDataWithRootObject: root
                                  requiringSecureCoding: YES error: &e];
  if (!d) NSLog(@"ARCHIVE FAILED: %@", e);
  return d;
}

#define SCEN(n, desc) NSLog(@"\n[%d] %s", n, desc)

int main(void)
{
  @autoreleasepool
  {
    NSError *err;
    id out;

    NSData *strData  = arch(@"secret-string");
    NSData *numData  = arch(@(42));
    NSData *arrData  = arch((@[@"a", @"b", @(3)]));      /* strings + a number */
    NSData *dictData = arch((@{@"k": @"v", @(1): @(2)}));

    SCEN(1, "unarchivedObjectOfClasses:{NSNumber} on an NSString  (mismatch)");
    err = nil; out = [NSKeyedUnarchiver unarchivedObjectOfClasses: [NSSet setWithObject: [NSNumber class]] fromData: strData error: &err];
    NSLog(@"    -> %s", R(out, err));

    SCEN(2, "unarchivedObjectOfClasses:{NSString} on an NSString  (match)");
    err = nil; out = [NSKeyedUnarchiver unarchivedObjectOfClasses: [NSSet setWithObject: [NSString class]] fromData: strData error: &err];
    NSLog(@"    -> %s", R(out, err));

    SCEN(3, "unarchivedObjectOfClasses:{NSString} on an NSMutableString subclass instance");
    err = nil; out = [NSKeyedUnarchiver unarchivedObjectOfClasses: [NSSet setWithObject: [NSString class]] fromData: arch([@"hi" mutableCopy]) error: &err];
    NSLog(@"    -> %s  (does a subclass of an allowed class pass?)", R(out, err));

    SCEN(4, "unarchivedObjectOfClasses:{NSObject} on an NSString  (NSObject does NOT conform to NSSecureCoding)");
    err = nil; out = [NSKeyedUnarchiver unarchivedObjectOfClasses: [NSSet setWithObject: [NSObject class]] fromData: strData error: &err];
    NSLog(@"    -> %s", R(out, err));

    SCEN(5, "unarchivedObjectOfClasses:{NSArray} on an NSArray of strings+number  (elements NOT listed)");
    err = nil; out = [NSKeyedUnarchiver unarchivedObjectOfClasses: [NSSet setWithObject: [NSArray class]] fromData: arrData error: &err];
    NSLog(@"    -> %s  (are element classes implicitly allowed, or must be listed?)", R(out, err));

    SCEN(6, "unarchivedObjectOfClasses:{NSArray,NSString,NSNumber} on the same array  (all listed)");
    err = nil; out = [NSKeyedUnarchiver unarchivedObjectOfClasses: [NSSet setWithObjects: [NSArray class], [NSString class], [NSNumber class], nil] fromData: arrData error: &err];
    NSLog(@"    -> %s", R(out, err));

    SCEN(7, "unarchivedObjectOfClasses:{} (EMPTY set) on an NSString");
    err = nil; out = [NSKeyedUnarchiver unarchivedObjectOfClasses: [NSSet set] fromData: strData error: &err];
    NSLog(@"    -> %s  (does empty set imply plist classes, or reject everything?)", R(out, err));

    SCEN(8, "unarchivedObjectOfClasses:{NSNumber} on an NSNumber  (plist primitive, match)");
    err = nil; out = [NSKeyedUnarchiver unarchivedObjectOfClasses: [NSSet setWithObject: [NSNumber class]] fromData: numData error: &err];
    NSLog(@"    -> %s", R(out, err));

    SCEN(9, "unarchivedArrayOfObjectsOfClasses:{NSString} on an NSArray of strings+number");
    err = nil; out = [NSKeyedUnarchiver unarchivedArrayOfObjectsOfClasses: [NSSet setWithObject: [NSString class]] fromData: arrData error: &err];
    NSLog(@"    -> %s  (NSArray implicit? number element not listed)", R(out, err));

    SCEN(10, "unarchivedDictionaryWithKeysOfClasses:{NSString} objectsOfClasses:{NSString} on {str:str, num:num}");
    err = nil; out = [NSKeyedUnarchiver unarchivedDictionaryWithKeysOfClasses: [NSSet setWithObject: [NSString class]] objectsOfClasses: [NSSet setWithObject: [NSString class]] fromData: dictData error: &err];
    NSLog(@"    -> %s", R(out, err));

    SCEN(11, "requiresSecureCoding=YES then bare decodeObjectForKey: (no class list)");
    @try {
      NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData: strData error: &err];
      u.requiresSecureCoding = YES;
      id r = [u decodeObjectForKey: @"root"];
      NSLog(@"    -> returned %s (no raise)", r ? [[r description] UTF8String] : "(nil)");
    } @catch (NSException *ex) {
      NSLog(@"    -> RAISED %s: %s", [[ex name] UTF8String], [[ex reason] UTF8String]);
    }

    SCEN(12, "decodeObjectOfClasses:{NSNumber}forKey: (instance API) on an NSString value");
    @try {
      NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData: strData error: &err];
      u.requiresSecureCoding = YES;
      id r = [u decodeObjectOfClasses: [NSSet setWithObject: [NSNumber class]] forKey: @"root"];
      NSLog(@"    -> returned %s (no raise)", r ? [[r description] UTF8String] : "(nil)");
    } @catch (NSException *ex) {
      NSLog(@"    -> RAISED %s: %s", [[ex name] UTF8String], [[ex reason] UTF8String]);
    }
  }
  return 0;
}
