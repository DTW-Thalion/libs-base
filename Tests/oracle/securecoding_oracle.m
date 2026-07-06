/* NSSecureCoding behavior oracle (v2 — custom classes are where the real
 * enforcement lives; plist substrate classes turned out to be implicitly
 * allowed regardless of the class list). Apple Foundation on macOS:
 *   clang -fobjc-arc -framework Foundation securecoding_oracle.m -o oracle && ./oracle
 */
#import <Foundation/Foundation.h>

/* A custom class that conforms to NSSecureCoding. */
@interface Widget : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSString *name;
@end
@implementation Widget
+ (BOOL) supportsSecureCoding { return YES; }
- (void) encodeWithCoder: (NSCoder *)c { [c encodeObject: _name forKey: @"name"]; }
- (instancetype) initWithCoder: (NSCoder *)c
{ if ((self = [super init])) { _name = [c decodeObjectOfClass: [NSString class] forKey: @"name"]; } return self; }
- (NSString *) description { return [NSString stringWithFormat: @"<Widget:%@>", _name]; }
@end

/* A custom class that does NOT conform to NSSecureCoding (plain NSCoding). */
@interface Sneaky : NSObject <NSCoding>
@end
@implementation Sneaky
- (void) encodeWithCoder: (NSCoder *)c {}
- (instancetype) initWithCoder: (NSCoder *)c { return [super init]; }
- (NSString *) description { return @"<Sneaky>"; }
@end

static NSString *S1(id o) { return o ? [[o description] stringByReplacingOccurrencesOfString: @"\n" withString: @" "] : @"(nil)"; }
static const char *R(id o, NSError *e)
{
  static char b[600];
  snprintf(b, sizeof(b), "obj=%s | err=%s", [S1(o) UTF8String],
    e ? [[NSString stringWithFormat: @"%@ code=%ld: %@", [e domain], (long)[e code],
          [[e userInfo] objectForKey: NSLocalizedDescriptionKey]] UTF8String] : "(nil)");
  return b;
}
static NSData *archS(id root, BOOL secure)
{ NSError *e=nil; NSData *d=[NSKeyedArchiver archivedDataWithRootObject: root requiringSecureCoding: secure error: &e];
  if(!d) NSLog(@"  ARCHIVE FAILED: %@", e); return d; }
#define SET(...) [NSSet setWithObjects: __VA_ARGS__, nil]
#define SCEN(n, d) NSLog(@"[%d] %s", n, d)

int main(void)
{
  @autoreleasepool
  {
    NSError *err; id out;
    Widget *w = [Widget new]; w.name = @"secret";
    NSData *widgetData = archS(w, YES);
    NSData *arrWidget  = archS(@[w], YES);               /* array containing a Widget */
    NSData *sneakyData = archS([Sneaky new], NO);        /* non-secure archive */

    SCEN(1, "Widget archive, decode {Widget}  (match)");
    err=nil; out=[NSKeyedUnarchiver unarchivedObjectOfClasses: SET([Widget class]) fromData: widgetData error: &err];
    NSLog(@"    -> %s", R(out,err));

    SCEN(2, "Widget archive, decode {NSString}  (custom class NOT listed)");
    err=nil; out=[NSKeyedUnarchiver unarchivedObjectOfClasses: SET([NSString class]) fromData: widgetData error: &err];
    NSLog(@"    -> %s", R(out,err));

    SCEN(3, "Widget archive, decode {} EMPTY");
    err=nil; out=[NSKeyedUnarchiver unarchivedObjectOfClasses: [NSSet set] fromData: widgetData error: &err];
    NSLog(@"    -> %s", R(out,err));

    SCEN(4, "array[Widget], decode {NSArray} ONLY  (Widget not listed - does propagation catch it?)");
    err=nil; out=[NSKeyedUnarchiver unarchivedObjectOfClasses: SET([NSArray class]) fromData: arrWidget error: &err];
    NSLog(@"    -> %s", R(out,err));

    SCEN(5, "array[Widget], decode {NSArray, Widget}  (both listed)");
    err=nil; out=[NSKeyedUnarchiver unarchivedObjectOfClasses: SET([NSArray class],[Widget class]) fromData: arrWidget error: &err];
    NSLog(@"    -> %s", R(out,err));

    SCEN(6, "array[Widget], decode {Widget} ONLY  (NSArray not listed - is the container implicitly allowed?)");
    err=nil; out=[NSKeyedUnarchiver unarchivedObjectOfClasses: SET([Widget class]) fromData: arrWidget error: &err];
    NSLog(@"    -> %s", R(out,err));

    SCEN(7, "Sneaky (non-NSSecureCoding), decode {Sneaky}  (listed but doesn't conform)");
    err=nil; out=[NSKeyedUnarchiver unarchivedObjectOfClasses: SET([Sneaky class]) fromData: sneakyData error: &err];
    NSLog(@"    -> %s", R(out,err));

    SCEN(8, "Widget archive, requiresSecureCoding=YES + bare decodeObjectForKey: (no class list)");
    @try { NSKeyedUnarchiver *u=[[NSKeyedUnarchiver alloc] initForReadingFromData: widgetData error: &err];
      u.requiresSecureCoding=YES; id r=[u decodeObjectForKey: @"root"];
      NSLog(@"    -> returned %s (no raise)", [S1(r) UTF8String]); }
    @catch(NSException *ex){ NSLog(@"    -> RAISED %s: %s", [[ex name] UTF8String], [[ex reason] UTF8String]); }

    SCEN(9, "Widget archive, decode {Widget} via unarchivedArrayOfObjectsOfClasses (root is not an array)");
    err=nil; out=[NSKeyedUnarchiver unarchivedArrayOfObjectsOfClasses: SET([Widget class]) fromData: widgetData error: &err];
    NSLog(@"    -> %s", R(out,err));

    SCEN(10, "plist recap: {NSNumber} on an NSString  (implicit-allow confirmation)");
    err=nil; out=[NSKeyedUnarchiver unarchivedObjectOfClasses: SET([NSNumber class]) fromData: archS(@"hi", YES) error: &err];
    NSLog(@"    -> %s", R(out,err));
  }
  return 0;
}
