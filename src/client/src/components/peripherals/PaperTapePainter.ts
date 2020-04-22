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

export class PaperTapePainter {
    private drawPending: boolean = false;


    constructor(private canvas: HTMLCanvasElement) {

    }

    public update(buf: Uint8Array, pos: number) {
        if (!this.drawPending) {
            this.drawPending = true;
            requestAnimationFrame(() => this.draw(buf, pos));
        }
    }

    private draw(buf: Uint8Array, pos: number) {
        this.drawPending = false;

        const ctx = this.canvas.getContext('2d');
        if (!ctx) {
            return;
        }

        const w = ctx.canvas.width;
        const h = ctx.canvas.height;

        ctx.fillStyle = '#f4ec72';
        ctx.fillRect(0, 0, w, h);

        ctx.fillStyle = 'rgba(255, 255, 255, 255)';

        for (let i = 0; i < w / 10; i++) {
            const idx = pos + i;
            if (idx < buf.byteLength) {
                const x = 2 + 10 * i;
                const byte = buf[idx];
                this.drawByte(ctx, x, byte);
            }
        }
    }

    private drawByte(ctx: CanvasRenderingContext2D, x: number, byte: number) {
        for (let i = 0; i < 8; i++) {
            if ((byte & (1 << i)) != 0) {
                let y = 10 + (7 - i) * 10;
                if (i < 3) {
                    y += 5;
                }
                ctx.beginPath();
                ctx.arc(x, y, 4, 0, 2 * Math.PI);
                ctx.fill();
            }
        }
        ctx.beginPath();
        ctx.arc(x, 58, 2, 0, 2 * Math.PI);
        ctx.fill();
    }
}
