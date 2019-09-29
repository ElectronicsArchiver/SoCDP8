/*
 *   SoCDP8 - A PDP-8/I implementation on a SoC
 *   Copyright (C) 2019 Folke Will <folko@solhost.org>
 *
 *   This program is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU Affero General Public License as published by
 *   the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU Affero General Public License for more details.
 *
 *   You should have received a copy of the GNU Affero General Public License
 *   along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import { IOConfigEntry } from './IOConfigEntry';

export class IOController {
    private DELAY_MS: number = 10;
    private DEV_ID_CLEAR_FLAG = 0;
    private DEV_ID_FLAGS = 64;
    private ioMem: Buffer;
    private configEntries: IOConfigEntry[] = [];

    public constructor(ioBuf: Buffer) {
        this.ioMem = ioBuf;
    }

    public registerDevice(entry: IOConfigEntry): void {
        this.configEntries.push(entry);

        let config: number = 0;

        if (entry.setFlagOnWrite) {
            config |= 1 << 12;
        }
        config |= entry.iopForSkipFlag << 13;
        config |= entry.iopForFlagClear << 15;
        config |= entry.iopForFlagSet << 17;
        config |= entry.iopForACLoad << 19;
        config |= entry.iopForACClear << 21;
        config |= entry.iopForRegisterLoad << 23;
        config |= entry.iopForInterrupt << 25;

        this.ioMem.writeUInt32LE(config, entry.devId * 4);
    }

    public writeDeviceRegister(devId: number, data: number): void {
        let reg = this.ioMem.readUInt32LE(devId * 4);
        reg &= ~0o7777; // clear current data
        reg &= ~(1 << 27); // clear new data flag
        reg |= data & 0o7777; // set new data
        this.ioMem.writeUInt32LE(reg, devId * 4);
    }

    public readDeviceRegister(devId: number): [number, boolean] {
        let reg = this.ioMem.readUInt32LE(devId * 4);
        let isNewData = (reg & (1 << 27)) != 0;
        return [reg & 0o7777, isNewData];
    }

    public clearDeviceFlag(devId: number): void {
        this.ioMem.writeUInt32BE(devId, this.DEV_ID_CLEAR_FLAG);
    }

    public async runDeviceLoop(): Promise<void> {
        let sleep = require('util').promisify(setTimeout);
        while (true) {
            let flagsLo = this.ioMem.readUInt32LE(this.DEV_ID_FLAGS * 4);
            let flagsHi = this.ioMem.readUInt32LE((this.DEV_ID_FLAGS + 1) * 4);
            for (let entry of this.configEntries) {
                let flagSet = false;
                if (entry.devId < 32) {
                    flagSet = ((flagsLo & (1 << entry.devId)) != 0);
                } else {
                    flagSet = ((flagsHi & (1 << (entry.devId - 32))) != 0);
                }

                if (flagSet) {
                    entry.onFlagSet();
                } else {
                    entry.onFlagUnset();
                }
            }
            await sleep(this.DELAY_MS);
        }
    }
}