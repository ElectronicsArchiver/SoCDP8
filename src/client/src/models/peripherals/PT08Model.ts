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

import { PeripheralModel } from './PeripheralModel';
import { PT08Configuration, DeviceID } from '../../types/PeripheralTypes';
import { PaperTape } from '../../components/peripherals/PaperTape';
import { Terminal } from 'xterm';
import { observable, computed, action } from 'mobx';

export class PT08Model extends PeripheralModel {
    @observable
    private conf: PT08Configuration;

    @observable
    private readerTape_?: PaperTape;

    @observable
    private readerActive_: boolean = false;

    private xterm: Terminal;

    constructor(socket: SocketIOClient.Socket, conf: PT08Configuration) {
        super(socket);
        this.conf = conf;
        this.xterm = new Terminal();

        this.xterm.onData(data => {
            for (let i = 0; i < data.length; i++) {
                let chr = data.charCodeAt(i);

                if (this.conf.eightBit) {
                    chr |= 0x80;
                }

                this.socket.emit('peripheral-action', {
                    id: this.conf.id,
                    action: 'key-press',
                    data: chr
                });
            }
        });
    }

    public get connections(): number[] {
        switch (this.conf.id) {
            case DeviceID.DEV_ID_PT08: return [0o03, 0o04];
            case DeviceID.DEV_ID_TT1:  return [0o40, 0o41];
            case DeviceID.DEV_ID_TT2:  return [0o42, 0o43];
            case DeviceID.DEV_ID_TT3:  return [0o44, 0o45];
            case DeviceID.DEV_ID_TT4:  return [0o46, 0o47];
        }
    }

    @computed
    public get config(): PT08Configuration {
        return this.conf;
    }

    @action
    public updateConfig(newConf: PT08Configuration) {
        this.conf = newConf;
        this.socket.emit('peripheral-change-conf', {
            id: this.conf.id,
            config: this.conf,
        });
    }

    public get terminal(): Terminal {
        return this.xterm;
    }

    public onPeripheralAction(action: string, data: any) {
        switch (action) {
            case 'punch':
                this.onPunch(data.data);
                break;
            case 'readerPos':
                this.setReaderPos(data.data);
                break;
        }
    }

    private onPunch(data: number) {
        const chr = data & 0x7F;
        this.xterm.write(String.fromCodePoint(chr));
    }

    public readonly loadTape = async (file: File): Promise<void> => {
        const tape = await PaperTape.fromFile(file);
        this.socket.emit('peripheral-action', {
            id: this.conf.id,
            action: 'reader-tape-set',
            data: tape.buffer.buffer
        });
        this.setReaderTape(tape);
    }

    @action
    private setReaderTape(tape: PaperTape) {
        this.readerTape_ = tape;
    }

    @action
    private setReaderPos(pos: number) {
        if (this.readerTape_) {
            this.readerTape_.pos = pos;
        }
    }

    @computed
    public get readerTape(): PaperTape | undefined {
        return this.readerTape_;
    }

    @computed
    public get readerPos(): number {
        return this.readerPos;
    }

    @action
    public setReaderActive(active: boolean) {
        this.readerActive_ = active;
        this.socket.emit('peripheral-action', {
            id: this.conf.id,
            action: 'reader-set-active',
            data: active
        });
    };

    @computed
    public get readerActive(): boolean {
        return this.readerActive_;
    }
}