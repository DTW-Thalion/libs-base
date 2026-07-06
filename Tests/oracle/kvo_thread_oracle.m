/* Concurrent KVO oracle for gnustep/libs-base issue #613.
 *
 * Replicates HendrikHuebner's setup: a `derived` key that depends on the
 * key paths `left.token` and `right.token`, observed on a single Holder, then
 * exercises the four concurrent-mutation scenarios from the issue and reports,
 * per scenario, the write count, the observed-notification count, and whether
 * an exception (or crash) occurred.
 *
 * Built to compile and run BOTH against Apple's Foundation (the oracle:
 *   clang -fobjc-arc -framework Foundation kvo_thread_oracle.m -o oracle) and
 * under GNUstep (for the A/B contrast that is the subject of #613).
 */

#import <Foundation/Foundation.h>
#import <pthread.h>
#import <stdatomic.h>

/* ---- Fixtures --------------------------------------------------------- */

@interface Value : NSObject
@property (nonatomic, copy) NSString *token;
@end
@implementation Value
@end

@interface Holder : NSObject
@property (nonatomic, retain) Value *left;
@property (nonatomic, retain) Value *right;
@property (nonatomic, readonly) NSString *derived;
@end
@implementation Holder
- (NSString *) derived
{
  return [NSString stringWithFormat: @"%@|%@",
    self.left.token, self.right.token];
}
+ (NSSet *) keyPathsForValuesAffectingDerived
{
  return [NSSet setWithObjects: @"left.token", @"right.token", nil];
}
@end

@interface Observer : NSObject
@end
@implementation Observer
{
@public
  _Atomic(long) count;
}
- (void) observeValueForKeyPath: (NSString *)keyPath
		       ofObject: (id)object
			 change: (NSDictionary *)change
			context: (void *)context
{
  atomic_fetch_add_explicit(&count, 1, memory_order_relaxed);
}
@end

/* ---- Concurrency harness ---------------------------------------------- */

static void *kCtx = &kCtx;

typedef enum { S_LEFT_TOKEN, S_REPLACE_LEFT, S_SPLIT_TOKENS, S_SPLIT_REPLACE }
  Scenario;

typedef struct {
  Holder		*holder;
  Scenario		scenario;
  int			tid;
  int			iters;
  _Atomic(long)		*writes;
  _Atomic(int)		*stop;
  char			exName[128];
  char			exReason[256];
  int			threw;
} ThreadArg;

static Value *
newValue(NSString *tok)
{
  Value *v = [Value new];
  v.token = tok;
  return v;
}

static void *
worker(void *raw)
{
  ThreadArg *a = (ThreadArg *)raw;
  @autoreleasepool
    {
      int i;
      for (i = 0; i < a->iters; i++)
	{
	  if (atomic_load_explicit(a->stop, memory_order_relaxed))
	    break;
	  @try
	    {
	      switch (a->scenario)
		{
		  case S_LEFT_TOKEN:
		    a->holder.left.token =
		      [NSString stringWithFormat: @"L%d-%d", a->tid, i];
		    break;
		  case S_REPLACE_LEFT:
		    a->holder.left =
		      newValue([NSString stringWithFormat: @"L%d-%d", a->tid, i]);
		    break;
		  case S_SPLIT_TOKENS:
		    if (a->tid & 1)
		      a->holder.right.token =
			[NSString stringWithFormat: @"R%d-%d", a->tid, i];
		    else
		      a->holder.left.token =
			[NSString stringWithFormat: @"L%d-%d", a->tid, i];
		    break;
		  case S_SPLIT_REPLACE:
		    if (a->tid & 1)
		      a->holder.right =
			newValue([NSString stringWithFormat: @"R%d-%d", a->tid, i]);
		    else
		      a->holder.left =
			newValue([NSString stringWithFormat: @"L%d-%d", a->tid, i]);
		    break;
		}
	      atomic_fetch_add_explicit(a->writes, 1, memory_order_relaxed);
	    }
	  @catch (NSException *e)
	    {
	      a->threw = 1;
	      strncpy(a->exName, [[e name] UTF8String] ?: "?", 127);
	      strncpy(a->exReason, [[e reason] UTF8String] ?: "?", 255);
	      atomic_store_explicit(a->stop, 1, memory_order_relaxed);
	      break;
	    }
	}
    }
  return NULL;
}

static void
runScenario(const char *label, Scenario s, int threads, int iters, int rep)
{
  int r;
  int threwCount = 0;
  char firstEx[128] = "", firstReason[256] = "";

  for (r = 0; r < rep; r++)
    {
      @autoreleasepool
	{
	  Holder *h = [Holder new];
	  h.left = newValue(@"l0");
	  h.right = newValue(@"r0");
	  Observer *obs = [Observer new];
	  atomic_store(&obs->count, 0);

	  [h addObserver: obs
	      forKeyPath: @"derived"
		 options: NSKeyValueObservingOptionNew
		 context: kCtx];

	  _Atomic(long) writes = 0;
	  _Atomic(int) stop = 0;
	  pthread_t tids[64];
	  ThreadArg args[64];
	  int t;

	  if (threads > 64) threads = 64;
	  for (t = 0; t < threads; t++)
	    {
	      memset(&args[t], 0, sizeof(ThreadArg));
	      args[t].holder = h;
	      args[t].scenario = s;
	      args[t].tid = t;
	      args[t].iters = iters;
	      args[t].writes = &writes;
	      args[t].stop = &stop;
	      pthread_create(&tids[t], NULL, worker, &args[t]);
	    }
	  for (t = 0; t < threads; t++)
	    pthread_join(tids[t], NULL);

	  int anyThrew = 0;
	  for (t = 0; t < threads; t++)
	    if (args[t].threw)
	      {
		anyThrew = 1;
		if (firstEx[0] == '\0')
		  {
		    strncpy(firstEx, args[t].exName, 127);
		    strncpy(firstReason, args[t].exReason, 255);
		  }
	      }
	  if (anyThrew) threwCount++;

	  long w = atomic_load(&writes);
	  long n = atomic_load(&obs->count);
	  printf("  [rep %d] writes=%ld notifications=%ld match=%s%s\n",
	    r, w, n, (w == n ? "YES" : "NO"),
	    anyThrew ? " EXCEPTION" : "");

	  @try { [h removeObserver: obs forKeyPath: @"derived" context: kCtx]; }
	  @catch (NSException *e) { /* graph may be corrupt after a throw */ }
	}
    }

  printf("[%s] threads=%d iters=%d reps=%d -> threw in %d/%d reps",
    label, threads, iters, rep, threwCount, rep);
  if (firstEx[0])
    printf("  firstException=%s reason=\"%s\"", firstEx, firstReason);
  printf("\n\n");
  fflush(stdout);
}

int
main(int argc, char **argv)
{
  /* One scenario per process invocation (argv[1] = 1..4) so that a crash in
   * one scenario does not suppress the data for the others.  With no argument
   * all four run in-process.
   */
  int only = (argc > 1) ? atoi(argv[1]) : 0;

  setvbuf(stdout, NULL, _IONBF, 0);
  @autoreleasepool
    {
#if defined(GNUSTEP)
      printf("=== Runtime: GNUstep ===\n");
#else
      printf("=== Runtime: Apple Foundation ===\n");
#endif

      /* Sanity: confirm the dependent-key graph fires at all. */
      {
	Holder *h = [Holder new];
	h.left = newValue(@"l0"); h.right = newValue(@"r0");
	Observer *obs = [Observer new]; atomic_store(&obs->count, 0);
	[h addObserver: obs forKeyPath: @"derived"
	    options: NSKeyValueObservingOptionNew context: kCtx];
	h.left.token = @"x";          /* affects derived via left.token   */
	h.left = newValue(@"y");      /* affects derived via left replace */
	h.right.token = @"z";         /* affects derived via right.token  */
	printf("sanity: 3 single-threaded affecting changes -> %ld notifications "
	  "(expect 3)\n\n", (long)atomic_load(&obs->count));
	[h removeObserver: obs forKeyPath: @"derived" context: kCtx];
      }

      int T = 8, K = 20000, R = 5;
      if (only == 0 || only == 1)
	runScenario("1: concurrent left.token",        S_LEFT_TOKEN,    T, K, R);
      if (only == 0 || only == 2)
	runScenario("2: concurrent replace left",      S_REPLACE_LEFT,  T, K, R);
      if (only == 0 || only == 3)
	runScenario("3: split left.token/right.token", S_SPLIT_TOKENS,  T, K, R);
      if (only == 0 || only == 4)
	runScenario("4: concurrent replace left+right",S_SPLIT_REPLACE, T, K, R);

      printf("=== done ===\n");
    }
  return 0;
}
