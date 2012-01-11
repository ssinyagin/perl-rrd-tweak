#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define RRD_EXPORT_DEPRECATED
#include <rrd.h>

/*
  Local Variables:
  mode: cperl
  indent-tabs-mode: nil
  End:
*/


MODULE = RRD::Tweak


void
load_file(SV *self, char *filename)
  INIT:
    rrd_file_t *rrd_file;
    rrd_t     rrd;
    rrd_value_t value;
  CODE:
{
    rrd_init(&rrd);

    rrd_file = rrd_open(filename, &rrd, RRD_READONLY | RRD_READAHEAD);
    if (rrd_file == NULL) {
        rrd_free(&rrd);
        croak("Cannot open RRD file: $!");
    }

    rrd_free(&rrd);
}






