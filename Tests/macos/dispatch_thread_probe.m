/* Measures, on OS X, what gnustep/libs-base#428 is about: is the NSThread
 * data of a libdispatch worker thread released, and when?
 *
 * Two cases:
 *
 *   reuse - a worker runs several work items in turn.  Does it keep the same
 *           NSThread and the same -threadDictionary contents between them?
 *   many  - several workers run at once, then the process idles.  Does the
 *           per-thread data get released while the process is still running?
 *
 * A Canary in -threadDictionary logs its -dealloc, and a pthread TSD
 * destructor of our own logs whether the thread ever exits and runs
 * destructors at all.
 *
 * Build: clang -framework Foundation dispatch_thread_probe.m -o probe
 */
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

static pthread_key_t	probeKey;
static volatile int	dtorCount = 0;
static volatile int	canaryCount = 0;
static volatile int	willExitCount = 0;
static double		t0 = 0.0;

static double
now(void)
{
  struct timespec ts;

  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec / 1.0e9;
}

#define	EL	(now() - t0)

static void
probeDtor(void *v)
{
  __sync_fetch_and_add(&dtorCount, 1);
  fprintf(stderr, "[probe] %7.3fs  TSD destructor ran on tid %lu\n",
    EL, (unsigned long)pthread_self());
}

@interface Canary : NSObject
@end

@implementation Canary
- (void) dealloc
{
  __sync_fetch_and_add(&canaryCount, 1);
  fprintf(stderr, "[probe] %7.3fs  Canary dealloc on tid %lu\n",
    EL, (unsigned long)pthread_self());
  [super dealloc];
}
@end

@interface Watcher : NSObject
- (void) willExit: (NSNotification*)n;
@end

@implementation Watcher
- (void) willExit: (NSNotification*)n
{
  __sync_fetch_and_add(&willExitCount, 1);
  fprintf(stderr, "[probe] %7.3fs  NSThreadWillExit on tid %lu\n",
    EL, (unsigned long)pthread_self());
}
@end

int
main(int argc, char **argv)
{
  const char	*mode = (argc > 1) ? argv[1] : "reuse";
  int		 idle = (argc > 2) ? atoi(argv[2]) : 60;

  setvbuf(stdout, 0, _IONBF, 0);
  setvbuf(stderr, 0, _IONBF, 0);
  t0 = now();

  @autoreleasepool
    {
      Watcher	*w = [Watcher new];

      [[NSNotificationCenter defaultCenter]
	addObserver: w
	   selector: @selector(willExit:)
	       name: NSThreadWillExitNotification
	     object: nil];
      pthread_key_create(&probeKey, probeDtor);
      fprintf(stderr, "[probe] main tid %lu, mode %s, idle %ds\n",
	(unsigned long)pthread_self(), mode, idle);

      if (0 == strcmp(mode, "reuse"))
	{
	  dispatch_queue_t q
	    = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	  int		i;

	  for (i = 0; i < 6; i++)
	    {
	      dispatch_semaphore_t s = dispatch_semaphore_create(0);

	      dispatch_async(q, ^{
		@autoreleasepool
		  {
		    NSThread	*t = [NSThread currentThread];
		    id		 old;

		    old = [[t threadDictionary] objectForKey: @"canary"];
		    fprintf(stderr,
		      "[probe] %7.3fs item %d on tid %lu NSThread %p,"
		      " canary already there: %p\n",
		      EL, i, (unsigned long)pthread_self(), t, old);
		    if (nil == old)
		      {
			Canary	*c = [Canary new];

			[[t threadDictionary] setObject: c forKey: @"canary"];
			[c release];
		      }
		    pthread_setspecific(probeKey, (void*)0x1);
		  }
		dispatch_semaphore_signal(s);
	      });
	      dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER);
	    }
	}
      else if (0 == strcmp(mode, "many"))
	{
	  dispatch_queue_t q
	    = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	  dispatch_group_t g = dispatch_group_create();
	  int		i;

	  for (i = 0; i < 16; i++)
	    {
	      dispatch_group_async(g, q, ^{
		@autoreleasepool
		  {
		    NSThread	*t = [NSThread currentThread];
		    Canary	*c = [Canary new];

		    fprintf(stderr,
		      "[probe] %7.3fs worker on tid %lu NSThread %p\n",
		      EL, (unsigned long)pthread_self(), t);
		    [[t threadDictionary] setObject: c forKey: @"canary"];
		    [c release];
		    pthread_setspecific(probeKey, (void*)0x1);
		    usleep(200000);
		  }
	      });
	    }
	  dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
	}
      else
	{
	  fprintf(stderr, "usage: %s reuse|many [idle]\n", argv[0]);
	  return 2;
	}

      fprintf(stderr, "[probe] %7.3fs work done, idling %ds\n", EL, idle);
      sleep(idle);
      fprintf(stderr,
	"[probe] RESULT %s: tsd_destructors=%d canary_deallocs=%d"
	" willExit=%d\n",
	mode, dtorCount, canaryCount, willExitCount);
    }
  return 0;
}
