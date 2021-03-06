/*
 * This file is part of the coreboot project.
 *
 * Copyright 2018 Google Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 2 of the License.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */

#include <arch/cpu.h>
#include <assert.h>
#include <baseboard/variants.h>
#include <chip.h>
#include <device/device.h>
#include <ec/google/chromeec/ec.h>
#include <smbios.h>
#include <soc/ramstage.h>
#include <string.h>

#define SKU_UNKNOWN	0xFFFF
#define SKU_0_NAMI	0x3A7B
#define SKU_1_VAYNE	0x3A63
#define SKU_2_VAYNE	0x3A7F

static uint16_t board_sku_id(void)
{
	static int sku_id = -1;
	uint32_t id;
	if (sku_id >= 0)
		return sku_id;
	if (google_chromeec_cbi_get_sku_id(&id))
		return SKU_UNKNOWN;
	sku_id = id;
	return sku_id;
}

void variant_devtree_update(void)
{
	/* Override dev tree settings per board */
	uint16_t sku_id = board_sku_id();
	device_t root = SA_DEV_ROOT;
	config_t *cfg = root->chip_info;
	switch (sku_id) {
	case SKU_1_VAYNE:
		cfg->usb2_ports[5].enable = 0;//rear camera
		break;
	default:
		break;
	}
}

const char *smbios_mainboard_sku(void)
{
	static char sku_str[9]; /* sku{0..65535} (basically up to FFFF) */

	snprintf(sku_str, sizeof(sku_str), "sku%d", board_sku_id());

	return sku_str;
}
