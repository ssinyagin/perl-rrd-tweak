#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <errno.h>
#include <string.h>
#include <time.h>

#define RRD_EXPORT_DEPRECATED
#include <rrd.h>

#ifndef RRD_READONLY
/* these are defined in rrd_tool.h and unavailable for use outside of rrdtool */
#define RRD_READONLY    (1<<0)
#define RRD_READWRITE   (1<<1)
#define RRD_CREAT       (1<<2)
#define RRD_READAHEAD   (1<<3)
#define RRD_COPY        (1<<4)
#define RRD_EXCL        (1<<5)
#endif



/*
  Local Variables:
  mode: c
  indent-tabs-mode: nil
  End:
*/


MODULE = RRD::Tweak


void
load_file(HV *self, char *filename)
  INIT:
    rrd_file_t *rrd_file;
    rrd_t     rrd;
    rrd_value_t value;
    unsigned int i, ii;
    HV *ds_list;
    HV *ds_params;
  CODE:
  {
      /* This function is derived from rrd_dump.c */
      
      rrd_init(&rrd);
      
      rrd_file = rrd_open(filename, &rrd, RRD_READONLY | RRD_READAHEAD);
      if (rrd_file == NULL) {
          rrd_free(&rrd);
          croak("Cannot open RRD file \"%s\": %s", filename, strerror(errno));
      }

      # Read the static header
      hv_store(self, "version", 7, newSVuv(atoi(rrd.stat_head->version)), 0);
      hv_store(self, "pdp_step", 8, newSVuv(rrd.stat_head->pdp_step), 0);

      # Read the live header
      hv_store(self, "last_up", 7, newSVuv(rrd.live_head->last_up), 0);

      ds_list = newHV();
      for (i = 0; i < rrd.stat_head->ds_cnt; i++) {
          
          ds_params = newHV();
          hv_store(ds_params, "type", 4, newSVpv(rrd.ds_def[i].dst, 20), 0);

          if( strcmp(rrd.ds_def[i].dst, "COMPUTE") != 0 ) {
              
              /* heartbit */
              hv_store(ds_params, "hb", 2,
                       newSVuv(rrd.ds_def[i].par[DS_mrhb_cnt].u_cnt), 0);
              
              /* min and max */
              hv_store(ds_params, "min", 3,
                       newSVnv(rrd.ds_def[i].par[DS_min_val].u_val), 0);
              hv_store(ds_params, "max", 3,
                       newSVnv(rrd.ds_def[i].par[DS_max_val].u_val), 0);
              
          } else {   /* COMPUTE */
              croak("COMPUTE datasource parsing is not yet supported");
          }
          
          hv_store(ds_list, rrd.ds_def[i].ds_nam, 20,
                   newRV((SV *) ds_params), 0);
      }

      hv_store(self, "ds", 2, newRV((SV *) ds_list), 0);
      rrd_free(&rrd);
  }






