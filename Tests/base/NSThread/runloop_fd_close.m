#import "ObjectTesting.h"
#import <Foundation/NSThread.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSDate.h>

#if defined(__linux__)

#include <pthread.h>
#include <sys/syscall.h>
#include <unistd.h>

/* These definitions take the place of the C library's for the calls
 * the base library makes, so the test can see which descriptor the
 * thread's run loop is given and how often that thread closes it.
 * Once closed, the number may be given to something else and closed
 * again elsewhere, so only the thread's own closes are counted.
 */
static volatile int	recording = 0;
static volatile int	watched = -1;
static volatile int	closes = 0;
static pthread_t	owner;

int
eventfd(unsigned int initval, int flags)
{
  int	fd = (int)syscall(SYS_eventfd2, initval, flags);

  if (recording && fd >= 0 && watched < 0)
    {
      owner = pthread_self();
      watched = fd;
    }
  return fd;
}

int
close(int fd)
{
  if (fd >= 0 && fd == watched && pthread_equal(pthread_self(), owner))
    {
      __sync_fetch_and_add(&closes, 1);
    }
  return (int)syscall(SYS_close, fd);
}

@interface	RunLoopUser : NSObject
- (void) run;
@end

@implementation	RunLoopUser
- (void) run
{
  recording = 1;
  [NSRunLoop currentRunLoop];
  recording = 0;
}
@end

int
main(void)
{
  START_SET("NSThread run loop descriptor")
    RunLoopUser	*user = AUTORELEASE([RunLoopUser new]);
    NSThread	*thread;
    NSDate	*limit;

    thread = AUTORELEASE([[NSThread alloc] initWithTarget: user
                                                 selector: @selector(run)
                                                   object: nil]);
    [thread start];
    limit = [NSDate dateWithTimeIntervalSinceNow: 10.0];
    while (closes == 0 && [limit timeIntervalSinceNow] > 0)
      {
        [NSThread sleepForTimeInterval: 0.01];
      }
    /* Both closes, when there are two, are made by one call as the
     * thread exits, so a short wait sees the second.
     */
    [NSThread sleepForTimeInterval: 0.2];

    PASS(watched >= 0, "a thread's run loop is given an eventfd")
    PASS(closes == 1,
      "the eventfd is closed once when its thread exits (closes: %d)",
      closes)
  END_SET("NSThread run loop descriptor")
  return 0;
}

#else

int
main(void)
{
  START_SET("NSThread run loop descriptor")
    SKIP("the run loop uses eventfd on Linux only")
  END_SET("NSThread run loop descriptor")
  return 0;
}

#endif
