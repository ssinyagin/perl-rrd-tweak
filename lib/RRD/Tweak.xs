/* Emacs formatting hints */
/*
  Local Variables:
  mode: c
  indent-tabs-mode: nil
  End:
*/


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


/* this is not yet implemented in RRDtool -- with the hopes for a
   better future */
#if defined(RRD_TOOL_VERSION) && RRD_TOOL_VERSION > 10040999
#define HAS_RRD_RPN_COMPACT2STR
#else
/* extract from rrd_format.c */
#define converter(VV,VVV)                       \
   if (strcmp(#VV, string) == 0) return VVV;

static enum cf_en rrd_cf_conv(
    const char *string)
{
    
    converter(AVERAGE, CF_AVERAGE)
        converter(MIN, CF_MINIMUM)
        converter(MAX, CF_MAXIMUM)
        converter(LAST, CF_LAST)
        converter(HWPREDICT, CF_HWPREDICT)
        converter(MHWPREDICT, CF_MHWPREDICT)
        converter(DEVPREDICT, CF_DEVPREDICT)
        converter(SEASONAL, CF_SEASONAL)
        converter(DEVSEASONAL, CF_DEVSEASONAL)
        converter(FAILURES, CF_FAILURES)
        rrd_set_error("unknown consolidation function '%s'", string);
    return (enum cf_en)(-1);
}
#endif




MODULE = RRD::Tweak


void
load_file(HV *self, char *filename)
  INIT:
    off_t        rra_base, rra_start, rra_next;
    rrd_file_t   *rrd_file;
    rrd_t        rrd;
    rrd_value_t  value;
    unsigned int i, ii;
    HV           *ds_list;
    AV           *rra_list;
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

      /* process datasources */
      ds_list = newHV();
      for (i = 0; i < rrd.stat_head->ds_cnt; i++) {
          HV *ds_params;
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
#ifdef HAS_RRD_RPN_COMPACT2STR
              char     *str = NULL;
              SV *sv = newSV(0);
              
              /* at the moment there's only non-public rpn_compact2str
              in rrdtool */
              rrd_rpn_compact2str((rpn_cdefds_t *)
                                  &(rrd.ds_def[i].par[DS_cdef]),
                                  rrd.ds_def, &str);
              /* store a null-terminated string in SV */
              sv_setpv(sv, str);
              hv_store(ds_params, "rpn", 3, sv, 0);
              free(str);
#else
              croak("COMPUTE datasource parsing is not yet supported");
#endif
          }

          /* last DS value is stored as string */
          hv_store(ds_params, "last_ds", 7,
                   newSVpv(rrd.pdp_prep[i].last_ds, 30), 0);

          /* scratch value */
          hv_store(ds_params, "scratch", 7,
                   newSVnv(rrd.pdp_prep[i].scratch[PDP_val].u_val), 0);

          /* unknown seconds */
          hv_store(ds_params, "unknown_sec", 11,
                   newSVuv(rrd.pdp_prep[i].scratch[PDP_unkn_sec_cnt].u_cnt), 0);

          /* done with this DS -- store it into ds_list hash */
          hv_store(ds_list, rrd.ds_def[i].ds_nam, 20,
                   newRV((SV *) ds_params), 0);
      }
                
      /* done with datasiurces -- attach ds_list as $self->{ds} */
      hv_store(self, "ds", 2, newRV((SV *) ds_list), 0);

      
      /* process RRA's */
      rra_list = newAV();
      rra_base = rrd_file->header_len;
      rra_next = rra_base;
      for (i = 0; i < rrd.stat_head->rra_cnt; i++) {
          long      timer = 0;
          /* hash with RRA attributes */
          HV *rra_params = newHV();
          /* hash with CDP preparation values for each DS */
          HV *rra_cdp_prep = newHV(); 
          
          /* process RRA definition */
          
          rra_start = rra_next;
          rra_next += (rrd.stat_head->ds_cnt
                       * rrd.rra_def[i].row_cnt * sizeof(rrd_value_t));

          hv_store(rra_params, "cf", 2,
                   newSVpv(rrd.rra_def[i].cf_nam, 20), 0);
          
          hv_store(rra_params, "pdp_per_row", 11,
                   newSVuv(rrd.rra_def[i].pdp_cnt), 0);
          
          /* RRA parameters */
          switch (rrd_cf_conv(rrd.rra_def[i].cf_nam)) {
              
          case CF_HWPREDICT:
          case CF_MHWPREDICT:
              hv_store(rra_params, "hw_alpha", 8,
                       newSVnv(rrd.rra_def[i].par[RRA_hw_alpha].u_val), 0);
              hv_store(rra_params, "hw_beta", 7,
                       newSVnv(rrd.rra_def[i].par[RRA_hw_beta].u_val), 0);
              hv_store(rra_params, "dependent_rra_idx", 17,
                       newSVuv(rrd.rra_def[i].par[
                                   RRA_dependent_rra_idx].u_cnt), 0);
            break;
            
          case CF_SEASONAL:
          case CF_DEVSEASONAL:
              hv_store(rra_params, "seasonal_gamma", 14,
                       newSVnv(rrd.rra_def[i].par[RRA_seasonal_gamma].u_val),
                       0);
              hv_store(rra_params, "seasonal_smooth_idx", 19,
                       newSVuv(rrd.rra_def[i].par[
                                   RRA_seasonal_smooth_idx].u_cnt), 0);
              if (atoi(rrd.stat_head->version) >= 4) {
                  hv_store(rra_params, "smoothing_window", 16,
                           newSVnv(rrd.rra_def[i].par[
                                       RRA_seasonal_smoothing_window].u_val),0);
              }

              hv_store(rra_params, "dependent_rra_idx", 17,
                       newSVuv(rrd.rra_def[i].par[
                                   RRA_dependent_rra_idx].u_cnt), 0);
            break;
            
          case CF_FAILURES:
              hv_store(rra_params, "delta_pos", 9,
                       newSVnv(rrd.rra_def[i].par[RRA_delta_pos].u_val), 0);
              hv_store(rra_params, "delta_neg", 9,
                       newSVnv(rrd.rra_def[i].par[RRA_delta_neg].u_val), 0);
              hv_store(rra_params, "window_len", 10,
                       newSVuv(rrd.rra_def[i].par[RRA_window_len].u_cnt), 0);
              hv_store(rra_params, "failure_threshold", 17,
                       newSVuv(rrd.rra_def[i].par[
                                   RRA_failure_threshold].u_cnt), 0);
              
              /* fall thru */
          case CF_DEVPREDICT:
              hv_store(rra_params, "dependent_rra_idx", 17,
                       newSVuv(rrd.rra_def[i].par[
                                   RRA_dependent_rra_idx].u_cnt), 0);
              break;
              
          case CF_AVERAGE:
          case CF_MAXIMUM:
          case CF_MINIMUM:
          case CF_LAST:
          default:
              hv_store(rra_params, "xff", 3,
                       newSVnv(rrd.rra_def[i].par[RRA_cdp_xff_val].u_val), 0);
              break;
          }

          /* extract cdp_prep for each DS for this RRA */
          for (ii = 0; ii < rrd.stat_head->ds_cnt; ii++) {
              unsigned long ivalue;
              HV *ds_cdp_prep = newHV();  /* per-DS CDP preparaion values */

              switch (rrd_cf_conv(rrd.rra_def[i].cf_nam)) {
                  
              case CF_HWPREDICT:
              case CF_MHWPREDICT:
                  value = rrd.cdp_prep[i * rrd.stat_head->ds_cnt + ii].
                      scratch[CDP_hw_intercept].u_val;
                  hv_store(ds_cdp_prep, "intercept", 9, newSVnv(value), 0);
                  
                  value = rrd.cdp_prep[i * rrd.stat_head->ds_cnt + ii].
                      scratch[CDP_hw_last_intercept].u_val;
                  hv_store(ds_cdp_prep, "last_intercept", 14,
                           newSVnv(value), 0);

                  value = rrd.cdp_prep[i * rrd.stat_head->ds_cnt + ii].
                      scratch[CDP_hw_slope].u_val;
                  hv_store(ds_cdp_prep, "slope", 5, newSVnv(value), 0);

                  value = rrd.cdp_prep[i * rrd.stat_head->ds_cnt + ii].
                      scratch[CDP_hw_last_slope].u_val;
                  hv_store(ds_cdp_prep, "last_slope", 10, newSVnv(value), 0);

                  
                  ivalue = rrd.cdp_prep[i * rrd.stat_head->ds_cnt + ii].
                      scratch[CDP_null_count].u_cnt;
                  hv_store(ds_cdp_prep, "nan_count", 9, newSVuv(ivalue), 0);

                  ivalue = rrd.cdp_prep[i * rrd.stat_head->ds_cnt + ii].
                      scratch[CDP_last_null_count].u_cnt;
                  hv_store(ds_cdp_prep, "last_nan_count", 14,
                           newSVuv(ivalue), 0);
                  break;
                  
              case CF_SEASONAL:
              case CF_DEVSEASONAL:
                  value = rrd.cdp_prep[i * rrd.stat_head->ds_cnt + ii].
                      scratch[CDP_hw_seasonal].u_val;
                  hv_store(ds_cdp_prep, "seasonal", 8, newSVnv(value), 0);

                  value = rrd.cdp_prep[i * rrd.stat_head->ds_cnt + ii].
                      scratch[CDP_hw_last_seasonal].u_val;
                  hv_store(ds_cdp_prep, "last_seasonal", 13, newSVnv(value), 0);
                  
                  ivalue = rrd.cdp_prep[i * rrd.stat_head->ds_cnt + ii].
                      scratch[CDP_init_seasonal].u_cnt;
                  hv_store(ds_cdp_prep, "init_flag", 10,
                           newSVuv(ivalue), 0);
                  break;
                  
              case CF_DEVPREDICT:
                  break;
                  
              case CF_FAILURES:
              {
                  unsigned short vidx;
                  char *violations_array =
                      (char *)
                      ((void *)
                       rrd.cdp_prep[i * rrd.stat_head->ds_cnt + ii].scratch);
                  
                  AV *history_array = newAV();
                  
                  for (vidx = 0;
                       vidx < rrd.rra_def[i].par[RRA_window_len].u_cnt;
                       ++vidx) {
                      av_push(history_array, newSVuv(violations_array[vidx]));
                  }

                  hv_store(ds_cdp_prep, "history", 7,
                           newRV((SV *) history_array), 0);
              }

              break;
              
              case CF_AVERAGE:
              case CF_MAXIMUM:
              case CF_MINIMUM:
              case CF_LAST:
              default:
                  value = rrd.cdp_prep[i * rrd.stat_head->ds_cnt + ii].
                      scratch[CDP_val].u_val;
                  hv_store(ds_cdp_prep, "value", 5, newSVnv(value), 0);

                  hv_store(ds_cdp_prep, "unknown_datapoints", 18,
                           newSVuv(
                               rrd.cdp_prep[i * rrd.stat_head->ds_cnt + ii].
                               scratch[CDP_unkn_pdp_cnt].u_cnt), 0);
                  break;
              }
              
              /* done with this DS CDP. store it into rra_cdp_prep hash */
              hv_store(rra_cdp_prep, rrd.ds_def[ii].ds_nam, 20,
                       newRV((SV *) ds_cdp_prep), 0);
          }

          /* done with all datasources. Store rra_cdp_prep into rra_params */
          hv_store(rra_params, "cdp_prep", 8,
                   newRV((SV *) rra_cdp_prep), 0);
          
          
          /* done with RRA definition, attach it to rra_list array */
          av_push(rra_list, newRV((SV *) rra_params));

          
          
          /* extract the RRA data */
          
      }
      
      /* done with RRA processing -- attach rra_list as $self->{rra} */
      hv_store(self, "rra", 3, newRV((SV *) rra_list), 0);

      
      rrd_free(&rrd);
  }







