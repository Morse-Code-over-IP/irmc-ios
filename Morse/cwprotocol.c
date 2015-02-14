#include <stdio.h>

#define OSX
#ifdef OSX
#include <mach/clock.h>
#include <mach/mach.h>
#endif

#include "cwprotocol.h"

int prepare_id (struct data_packet_format *id_packet, char *id)
{
	id_packet->command = DAT;
	id_packet->length = SIZE_DATA_PACKET_PAYLOAD;
	snprintf(id_packet->id, SIZE_ID, id, "%s");
	id_packet->sequence = 0;
	id_packet->n = 0;
	snprintf(id_packet->status, SIZE_ID, INTERFACE_VERSION);
	id_packet->a21 = 1;     /* These magic numbers was provided by Les Kerr */
	id_packet->a22 = 755;
	id_packet->a23 = 65535;

	return 0;
}


int prepare_tx (struct data_packet_format *tx_packet, char *id)
{
	int i;

	tx_packet->command = DAT;
	tx_packet->length = SIZE_DATA_PACKET_PAYLOAD;
	snprintf(tx_packet->id, SIZE_ID,  id, "%s");
	tx_packet->sequence = 0;
	tx_packet->n = 0;
	for(i = 1; i < 51; i++)tx_packet->code[i] = 0;
	tx_packet->a21 = 0; /* These magic numbers was provided by Les Kerr */
	tx_packet->a22 = 755;
	tx_packet->a23 = 16777215;
	snprintf(tx_packet->status, SIZE_STATUS, "?");
	
	return 0;
}



/* portable time, as listed in https://gist.github.com/jbenet/1087739  */
void current_utc_time(struct timespec *ts) {
    clock_serv_t cclock;
    mach_timespec_t mts;
    host_get_clock_service(mach_host_self(), CALENDAR_CLOCK, &cclock);
    clock_get_time(cclock, &mts);
    mach_port_deallocate(mach_task_self(), cclock);
    ts->tv_sec = mts.tv_sec;
    ts->tv_nsec = mts.tv_nsec;
}

/* a better clock() in milliseconds */
long fastclock(void)
{
    struct timespec t;
    long r;
    
    current_utc_time (&t);
    r = t.tv_sec * 1000;
    r = r + t.tv_nsec / 1000000;
    return r;
}




