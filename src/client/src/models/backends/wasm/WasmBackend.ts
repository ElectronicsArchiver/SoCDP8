/*
 *   SoCDP8 - A PDP-8/I implementation on a SoC
 *   Copyright (C) 2021 Folke Will <folko@solhost.org>
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

import { DeviceID, PeripheralConfiguration } from '../../../types/PeripheralTypes';
import { SystemConfiguration } from '../../../types/SystemConfiguration';
import { Backend } from '../Backend';
import { BackendListener } from '../BackendListener';
import { Wasm8Context } from './Wasm8Context';

export class WasmBackend implements Backend {
    private listener?: BackendListener;
    private pdp8: Wasm8Context;

    private systems: SystemConfiguration[] = [
        {
            id: "default",
            name: "default",
            description: "default",
            maxMemField: 7,
            cpuExtensions: {
                eae: true,
                kt8i: true,
            },
            peripherals: [
                {
                    id: DeviceID.DEV_ID_PT08,
                    eightBit: false,
                    autoCaps: true,
                    baudRate: 1200,
                },
                {
                    id: DeviceID.DEV_ID_PC04,
                    baudRate: 1200,
                },
                {
                    id: DeviceID.DEV_ID_TC08,
                    numTapes: 2,
                },
                {
                    id: DeviceID.DEV_ID_TT1,
                    baudRate: 1200,
                    eightBit: false,
                    autoCaps: true,
                },
                {
                    id: DeviceID.DEV_ID_TT2,
                    baudRate: 1200,
                    eightBit: false,
                    autoCaps: true,
                },
                {
                    id: DeviceID.DEV_ID_TT3,
                    baudRate: 1200,
                    eightBit: false,
                    autoCaps: true,
                },
                {
                    id: DeviceID.DEV_ID_TT4,
                    baudRate: 1200,
                    eightBit: false,
                    autoCaps: true,
                },
                {
                    id: DeviceID.DEV_ID_RF08,
                },
            ],
        },
    ];

    public constructor() {
        this.pdp8 = new Wasm8Context();
    }

    public async connect(listener: BackendListener) {
        this.listener = listener;

        await this.pdp8.create((dev, action, p1, p2) => this.onPeripheralAction(dev, action, p1, p2));

        this.setActiveSystem("default");

        this.listener.onConnect();

        const updateConsole = () => {
            listener.onConsoleState(this.pdp8.getConsoleState());
            requestAnimationFrame(updateConsole);
        }
        updateConsole();
    }

    public async readActiveSystem(): Promise<SystemConfiguration> {
        return this.systems[0];
    }

    public async saveActiveSystem(): Promise<boolean> {
        return true;
    }

    public async readSystems(): Promise<SystemConfiguration[]> {
        return this.systems;
    }

    public async createSystem(system: SystemConfiguration) {
    }

    public async setActiveSystem(id: string) {
        for (const sys of this.systems) {
            if (sys.id == id) {
                this.pdp8.configure(sys.maxMemField, sys.cpuExtensions.eae, sys.cpuExtensions.kt8i, false);

                for (const peripheral of this.systems[0].peripherals) {
                    this.changePeripheralConfig(peripheral.id, peripheral);
                }
                break;
            }
        }
    }

    public async deleteSystem(id: string) {
    }

    public async setPanelSwitch(sw: string, state: boolean): Promise<void> {
        this.pdp8.setSwitch(sw, state);
    }

    public async clearCore() {
        this.pdp8.clearCore();
    }

    public async writeCore(addr: number, fragment: number[]) {
        for (let i = 0; i < fragment.length; i++) {
            this.pdp8.writeCore(addr + i, fragment[i]);
        }
    }

    public async sendPeripheralAction(id: DeviceID, action: string, data: any): Promise<void> {
        if (
            id == DeviceID.DEV_ID_PT08 ||
            id == DeviceID.DEV_ID_TT1 ||
            id == DeviceID.DEV_ID_TT2 ||
            id == DeviceID.DEV_ID_TT3 ||
            id == DeviceID.DEV_ID_TT4
        ) {
            if (action == "key-press") {
                this.pdp8.sendPeripheralAction(id, 3, data, 0);
            } else if (action == "reader-tape-set") {
                const buf = data as ArrayBufferLike;
                this.pdp8.sendPeripheralActionBuffer(id, 4, buf);
            } else if (action == "reader-set-active") {
                this.pdp8.sendPeripheralAction(id, 5, data, 0);
            }
        } else if (id == DeviceID.DEV_ID_PC04) {
            if (action == "reader-tape-set") {
                const buf = data as ArrayBufferLike;
                this.pdp8.sendPeripheralActionBuffer(DeviceID.DEV_ID_PC04, 4, buf);
            } else if (action == "reader-set-active") {
                this.pdp8.sendPeripheralAction(DeviceID.DEV_ID_PC04, 5, data, 0);
            }
        } else if (id == DeviceID.DEV_ID_TC08) {
            if (action == "load-tape") {
                const unit = data.unit as number;
                const tapeData = data.tapeData as ArrayBuffer;
                this.pdp8.sendPeripheralActionBuffer(DeviceID.DEV_ID_TC08, 1 + unit, tapeData);
            }
        }
    }

    private tapeStatus: number[] = [];
    private async onPeripheralAction(dev: DeviceID, action: number, p1: number, p2: number) {
        if (!this.listener) {
            return;
        }

        switch (dev) {
            case DeviceID.DEV_ID_NULL:
                if (action == 4) {
                    const simSpeed = p1 / 10;
                    this.listener.onPerformanceReport(simSpeed);
                }
                break;
            case DeviceID.DEV_ID_PT08:
            case DeviceID.DEV_ID_TT1:
            case DeviceID.DEV_ID_TT2:
            case DeviceID.DEV_ID_TT3:
            case DeviceID.DEV_ID_TT4:
                if (action == 1) {
                    this.listener.onPeripheralEvent({
                        id: dev,
                        action: "readerPos",
                        data: p1,
                    });
                } else if (action == 2) {
                    this.listener.onPeripheralEvent({
                        id: dev,
                        action: "punch",
                        data: p1,
                    });
                }
                break;
            case DeviceID.DEV_ID_PC04:
                if (action == 1) {
                    this.listener.onPeripheralEvent({
                        id: DeviceID.DEV_ID_PC04,
                        action: "readerPos",
                        data: p1,
                    });
                } else if (action == 2) {
                    this.listener.onPeripheralEvent({
                        id: DeviceID.DEV_ID_PC04,
                        action: "punch",
                        data: p1,
                    });
                }
                break;
            case DeviceID.DEV_ID_TC08:
                if (action == 10) {
                    this.tapeStatus[p1] = p2;
                    if (p1 == 7) {
                        this.listener.onPeripheralEvent({
                            id: DeviceID.DEV_ID_TC08,
                            action: "status",
                            data: this.tapeStatus
                                .filter(x => x & 1)
                                .map((x, i) => { return {
                                    address: i,
                                    selected: this.tapeStatus[i] & 2,
                                    moving: this.tapeStatus[i] & 4,
                                    reverse: this.tapeStatus[i] & 8,
                                    writing: this.tapeStatus[i] & 16,
                                    normalizedPosition: ((this.tapeStatus[i] & 0xFFFF0000) >> 16) / 1000,
                            };}),
                        });
                    }
                }
                break;
        }
    }

    public async changePeripheralConfig(id: DeviceID, config: PeripheralConfiguration): Promise<void> {
        switch (config.id) {
            case DeviceID.DEV_ID_PT08:
            case DeviceID.DEV_ID_TT1:
            case DeviceID.DEV_ID_TT2:
            case DeviceID.DEV_ID_TT3:
            case DeviceID.DEV_ID_TT4:
                this.pdp8.sendPeripheralAction(id, 6, config.baudRate, 0);
                break;
            case DeviceID.DEV_ID_PC04:
                this.pdp8.sendPeripheralAction(id, 6, config.baudRate, 0);
                break;
            }
    }

    public async readPeripheralBlock(id: DeviceID, block: number): Promise<Uint16Array> {
        return Uint16Array.from([]);
    }
}
