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

import { mkdirSync, readdirSync, readFileSync } from 'fs';
import { SystemConfiguration, DEFAULT_SYSTEM_CONF } from '../types/SystemConfiguration';
import { randomBytes } from 'crypto';

export class SystemConfigurationList {
    private readonly sysDir: string;
    private configs: Map<string, SystemConfiguration> = new Map();

    constructor(private readonly baseDir: string) {
        this.sysDir = this.baseDir + '/systems/';
        mkdirSync(this.sysDir, {recursive: true});

        this.loadSystems();

        if (!this.configs.has('default')) {
            this.addState(DEFAULT_SYSTEM_CONF);
        }
    }

    public generateId() {
        return randomBytes(16).toString('hex');
    }

    public getDirForSystem(sys: SystemConfiguration) {
        const cleanName = sys.name.replace(/[^a-zA-Z0-9_]/g, '').replace(/ /g, '_');
        return `${this.sysDir}/${cleanName}-${sys.id}/`;
    }

    private loadSystems() {
        for(const stateDir of readdirSync(this.sysDir)) {
            try {
                const dir = this.sysDir + '/' + stateDir;

                const configJson = readFileSync(dir + '/system.json');
                const sys = JSON.parse(configJson.toString()) as SystemConfiguration;

                this.configs.set(sys.id, sys);
            } catch (e) {
                console.log('Skipping system ' + stateDir + ': ' + e);
            }
        }
    }

    public getSystems(): SystemConfiguration[] {
        const res: SystemConfiguration[] = [];

        for (const conf of this.configs.values()) {
            res.push(conf);
        }

        return res;
    }

    public findSystemById(id: string): SystemConfiguration {
        const config = this.configs.get(id);
        if (!config) {
            throw Error('Unknown system');
        }

        return config;
    }

    public addState(sys: SystemConfiguration) {
        if (this.configs.has(sys.id)) {
            throw Error('ID already exists');
        }

        this.configs.set(sys.id, sys);
    }
}