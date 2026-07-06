/* NSCalendar rangeOfUnit oracle. clang -framework Foundation calendar_oracle.m -o o && ./o */
#import <Foundation/Foundation.h>

static NSCalendar *gCal;
static NSDate *mkdate(int y,int mo,int d,int h,int mi,int s)
{
  NSDateComponents *c=[NSDateComponents new];
  c.year=y; c.month=mo; c.day=d; c.hour=h; c.minute=mi; c.second=s;
  return [gCal dateFromComponents:c];
}
static void RNG(const char *label, NSCalendarUnit small, NSCalendarUnit large, NSDate *d)
{
  NSRange r=[gCal rangeOfUnit:small inUnit:large forDate:d];
  if (r.location==NSNotFound) printf("%-26s -> {NSNotFound, %lu}\n", label, (unsigned long)r.length);
  else printf("%-26s -> {loc=%lu, len=%lu}\n", label, (unsigned long)r.location, (unsigned long)r.length);
}
static void INTV(const char *label, NSCalendarUnit u, NSDate *d)
{
  NSDate *start=nil; NSTimeInterval len=0;
  BOOL ok=[gCal rangeOfUnit:u startDate:&start interval:&len forDate:d];
  printf("%-26s -> ok=%d start=%s len=%.0fs (%.2f days)\n", label, ok,
    start?[[start description] UTF8String]:"(nil)", len, len/86400.0);
}

int main(void)
{
  @autoreleasepool {
    gCal=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    gCal.timeZone=[NSTimeZone timeZoneWithName:@"UTC"];

    printf("=== rangeOfUnit:inUnit:forDate: ===\n");
    RNG("Day in Month (Feb2015)", NSCalendarUnitDay, NSCalendarUnitMonth, mkdate(2015,2,15,0,0,0));
    RNG("Day in Month (Feb2016 leap)", NSCalendarUnitDay, NSCalendarUnitMonth, mkdate(2016,2,15,0,0,0));
    RNG("Day in Month (Jan)", NSCalendarUnitDay, NSCalendarUnitMonth, mkdate(2015,1,15,0,0,0));
    RNG("Day in Month (Apr)", NSCalendarUnitDay, NSCalendarUnitMonth, mkdate(2015,4,15,0,0,0));
    RNG("Day in Year (2015)", NSCalendarUnitDay, NSCalendarUnitYear, mkdate(2015,6,1,0,0,0));
    RNG("Day in Year (2016 leap)", NSCalendarUnitDay, NSCalendarUnitYear, mkdate(2016,6,1,0,0,0));
    RNG("Month in Year", NSCalendarUnitMonth, NSCalendarUnitYear, mkdate(2015,6,1,0,0,0));
    RNG("Day in Week", NSCalendarUnitDay, NSCalendarUnitWeekOfYear, mkdate(2015,6,1,0,0,0));
    RNG("Weekday in Week", NSCalendarUnitWeekday, NSCalendarUnitWeekOfYear, mkdate(2015,6,1,0,0,0));
    RNG("Hour in Day", NSCalendarUnitHour, NSCalendarUnitDay, mkdate(2015,6,1,0,0,0));
    RNG("Minute in Hour", NSCalendarUnitMinute, NSCalendarUnitHour, mkdate(2015,6,1,0,0,0));
    RNG("Second in Minute", NSCalendarUnitSecond, NSCalendarUnitMinute, mkdate(2015,6,1,0,0,0));
    RNG("WeekOfMonth in Month(Feb15)", NSCalendarUnitWeekOfMonth, NSCalendarUnitMonth, mkdate(2015,2,15,0,0,0));
    RNG("WeekOfYear in Year(2015)", NSCalendarUnitWeekOfYear, NSCalendarUnitYear, mkdate(2015,6,1,0,0,0));
    RNG("Month in Day (nonsense)", NSCalendarUnitMonth, NSCalendarUnitDay, mkdate(2015,6,1,0,0,0));
    RNG("Day in Day (same)", NSCalendarUnitDay, NSCalendarUnitDay, mkdate(2015,6,1,0,0,0));

    printf("\n=== rangeOfUnit:startDate:interval:forDate: ===\n");
    INTV("Month contains Feb15 2015", NSCalendarUnitMonth, mkdate(2015,2,15,12,30,0));
    INTV("Day contains Feb15 12:30", NSCalendarUnitDay, mkdate(2015,2,15,12,30,0));
    INTV("Year contains 2015", NSCalendarUnitYear, mkdate(2015,6,1,0,0,0));
    INTV("Hour contains 12:30:45", NSCalendarUnitHour, mkdate(2015,2,15,12,30,45));
  }
  return 0;
}
