/* NSCalendar rangeOfUnit oracle - full (smaller x larger) matrix.
 * clang -framework Foundation calendar_oracle.m -o o && ./o */
#import <Foundation/Foundation.h>

static NSCalendar *gCal;
static NSDate *D;   /* 2015-02-15 12:30:45 UTC (non-leap Feb) */

static struct { NSCalendarUnit u; const char *n; } U[] = {
  {NSCalendarUnitEra,"Era"}, {NSCalendarUnitYear,"Year"},
  {NSCalendarUnitMonth,"Month"}, {NSCalendarUnitWeekOfYear,"WeekOfYear"},
  {NSCalendarUnitWeekOfMonth,"WeekOfMonth"}, {NSCalendarUnitDay,"Day"},
  {NSCalendarUnitWeekday,"Weekday"}, {NSCalendarUnitWeekdayOrdinal,"WeekdayOrd"},
  {NSCalendarUnitHour,"Hour"}, {NSCalendarUnitMinute,"Minute"},
  {NSCalendarUnitSecond,"Second"},
};

int main(void)
{
  @autoreleasepool {
    int i, j, N = sizeof(U)/sizeof(U[0]);
    NSDateComponents *c = [NSDateComponents new];
    gCal = [[NSCalendar alloc] initWithCalendarIdentifier: NSCalendarIdentifierGregorian];
    gCal.timeZone = [NSTimeZone timeZoneWithName: @"UTC"];
    c.year=2015; c.month=2; c.day=15; c.hour=12; c.minute=30; c.second=45;
    D = [gCal dateFromComponents: c];

    printf("=== rangeOfUnit:(smaller) inUnit:(larger) forDate: 2015-02-15 (only VALID pairs) ===\n");
    for (i = 0; i < N; i++)
      for (j = 0; j < N; j++)
        {
          NSRange r = [gCal rangeOfUnit: U[i].u inUnit: U[j].u forDate: D];
          if (r.location != NSNotFound)
            printf("%-12s in %-12s -> {loc=%lu, len=%lu}\n",
              U[i].n, U[j].n, (unsigned long)r.location, (unsigned long)r.length);
        }
  }
  return 0;
}
