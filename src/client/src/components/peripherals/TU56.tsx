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

import React from "react";
import { observer } from 'mobx-react-lite';
import { DECTape } from '../../models/DECTape';

export interface TU56Props {
    left?: DECTape;
    right?: DECTape;
}

export const TU56: React.FunctionComponent<TU56Props> = observer(props => {
    const [painter, setPainter] = React.useState<TU56Painter>(new TU56Painter());
    const canvasRef = React.useRef<HTMLCanvasElement>(null);

    React.useEffect(() => {
        if (canvasRef.current) {
            const canvas = canvasRef.current;

            if (canvas.parentElement) {
                canvas.width = canvas.parentElement.scrollWidth;
                canvas.height = canvas.width * 0.5;
            }
            painter.setCanvas(canvas);
        }

        return () => {
            painter?.stop();
        };
    }, [painter]);

    React.useEffect(() => {
        painter.update(props.left, props.right);
    }, [painter, props.left, props.right]);

    return <canvas ref={canvasRef} />;
});

/*
 * Ported from https://github.com/wvdmark/pdp8/blob/master/NetBeansSource/PDP8-16/Devices/DTReel.java
 */
class TU56Painter {
    private readonly REEL_CENTER_X  = 0.5;
    private readonly REEL_CENTER_Y  = 0.65;
    private readonly PLATE_TOP_Y    = 0.03;
    private readonly GUIDE_BOTTOM_Y = 0.34;
    private readonly GUIDE_RIGHT_X  = 0.83;
    private readonly HUB_RADIUS     = 0.27;
    private readonly REEL_RADIUS    = 0.40;
    private readonly HEAD_LEFT_X    = 0.88;
    private readonly HEAD_TOP_Y     = 0.01;
    private readonly HEAD_TOP_Y1    = 0.05;
    private readonly HEAD_BOTTOM_Y  = 0.30;
    private readonly MIL            = 0.0015;

    private canvas?: HTMLCanvasElement;
    private leftTape?: DECTape;
    private rightTape?: DECTape;
    private stopped: boolean = false;

    public setCanvas(canvas: HTMLCanvasElement) {
        this.canvas = canvas;
        requestAnimationFrame((t) => this.draw(t));
    }

    public update(left?: DECTape, right?: DECTape) {
        this.leftTape = left;
        this.rightTape = right;
    }

    public stop() {
        this.stopped = true;
    }

    private draw(t: number) {
        const ctx = this.canvas?.getContext('2d');
        if (!ctx || this.stopped) {
            return;
        }

        const w = ctx.canvas.width;
        const h = ctx.canvas.height;

        ctx.fillStyle = '#000';
        ctx.fillRect(0, 0, w, h);

        const reelHeight = h * 0.7;
        const reelWidth = reelHeight * 5 / 8;

        this.drawHeader(ctx, 5, 5, 2 * reelWidth - 10, h * 0.3 - 5, this.leftTape);
        this.drawSystem(ctx, t, 0, h * 0.35, reelWidth, reelHeight, this.leftTape);

        this.drawHeader(ctx, w - 2 * reelWidth + 5, 5, 2 * reelWidth - 10, h * 0.3 - 5, this.rightTape);
        this.drawSystem(ctx, t, w - 2 * reelWidth , h * 0.35, reelWidth, reelHeight, this.rightTape);

        if (!this.stopped) {
            requestAnimationFrame((t) => this.draw(t));
        }
    }

    private drawSystem(ctx: CanvasRenderingContext2D, t: number, cx: number, cy: number, w: number, h: number, tape?: DECTape) {
        this.drawReel(ctx, t, cx, cy, w, h, false, tape);
        this.drawReel(ctx, t, cx + 2 * w - 1, cy, w, h, true, tape);
    }

    private drawHeader(ctx: CanvasRenderingContext2D, cx: number, cy: number, w: number, h: number, tape?: DECTape) {
        ctx.strokeStyle = '#FFF';
        ctx.lineWidth = 2;
        ctx.strokeRect(cx, cy, w, h);

        if (tape && tape.writing) {
            ctx.fillStyle = 'orange';
        } else {
            ctx.fillStyle = 'gray';
        }

        const writeLeft = cx + 0.05 * w;
        const writeTop = cy + 0.1 * h;
        const writeW = 0.1 * w;
        const writeH = 0.8 * h;
        ctx.fillRect(writeLeft, writeTop, writeW, writeH);

        if (tape && tape.selected) {
            ctx.fillStyle = 'orange';
        } else {
            ctx.fillStyle = 'gray';
        }

        const selLeft = cx + 0.85 * w;
        const selTop = cy + 0.1 * h;
        const selW = 0.1 * w;
        const selH = 0.8 * h;
        ctx.fillRect(selLeft, selTop, selW, selH);
    }

    private drawReel(ctx: CanvasRenderingContext2D, t: number, cx: number, cy: number, w: number, h: number, right: boolean, tape?: DECTape) {
        ctx.resetTransform();
        ctx.translate(cx, cy);
        if (right) {
            ctx.scale(-1, 1);
        }

        const reelX = this.REEL_CENTER_X * w;
        const reelY = this.REEL_CENTER_Y * h;
        const plateTopY = h * this.PLATE_TOP_Y;
        const guideBottomY = h * this.GUIDE_BOTTOM_Y;
        const guideRightX = w * this.GUIDE_RIGHT_X;
        const guideLeftX = w * this.GUIDE_RIGHT_X - h * this.GUIDE_BOTTOM_Y;
        const angle1 = Math.atan((guideRightX - reelX) / (reelY - guideBottomY));
        const distGuideReel = Math.sqrt((guideRightX - reelX) * (guideRightX - reelX) + (reelY - guideBottomY) * (reelY - guideBottomY));
        const headTopY = h * this.HEAD_TOP_Y;

        let reelRadius = 0;
        let hubRadius = 0;

        if ((w - reelX) > (h - reelY)) {
            reelRadius = (h - reelY) * this.REEL_RADIUS * 2;
            hubRadius = (h - reelY) * this.HUB_RADIUS * 2;
        } else {
            reelRadius = (w - reelX) * this.REEL_RADIUS * 2;
            hubRadius = (w - reelX) * this.HUB_RADIUS * 2;
        }

        this.drawHead(ctx, w, h);

        ctx.fillStyle = '#808080';
        ctx.fillRect(guideLeftX, plateTopY, guideRightX - guideLeftX, guideBottomY - plateTopY);

        ctx.strokeStyle = '#FFFFFF';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(guideLeftX, guideBottomY);
        ctx.lineTo(guideLeftX, plateTopY);
        ctx.lineTo(guideRightX, plateTopY);
        ctx.stroke();

        let startAng = 0;

        if (tape) {
            const reelLine = (right ? tape.normalizedPosition : (1 - tape.normalizedPosition)) * 0x100000;
            const windings = (Math.sqrt(1 + (this.MIL * reelLine / (150 * Math.PI * hubRadius * 4.5 / w))) - 1) / (2 * this.MIL);
            const tapeRadius = (windings * this.MIL + 1) * hubRadius;

            if (tape.moving) {
                startAng = (t % 1000) / 1000 * 2 * Math.PI;

                if (!right) {
                    startAng *= -1;
                }

                if (tape.reverse) {
                    startAng *= -1;
                }
            }

            ctx.strokeStyle = '#F00';
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(guideRightX, headTopY);
            ctx.lineTo(w, headTopY);
            ctx.stroke();

            const angle2 = Math.asin((tapeRadius - (guideRightX - guideLeftX)) / distGuideReel);
            const angle = angle1 + angle2;
            const gtx = (guideRightX - guideLeftX) * Math.cos(angle) * 0.98;
            const gty = (guideRightX - guideLeftX) * Math.sin(angle) * 0.98;
            const ll = distGuideReel * Math.cos(angle2);
            const ex = -ll * Math.sin(angle);
            const ey = ll * Math.cos(angle);

            ctx.beginPath();
            ctx.moveTo(guideRightX - gtx, guideBottomY - gty);
            ctx.lineTo(guideRightX - gtx + ex, guideBottomY - gty + ey);
            ctx.stroke();

            ctx.fillStyle = '#F00';
            ctx.beginPath();
            ctx.arc(reelX, reelY, tapeRadius, 0, 2 * Math.PI);
            ctx.fill();

            ctx.fillStyle = 'rgba(255, 255, 255, 0.8)';
            ctx.beginPath();
            ctx.arc(reelX, reelY, reelRadius, 0, 2 * Math.PI);
            ctx.fill();
        }
        ctx.fillStyle = '#000000';
        ctx.beginPath();
        ctx.arc(reelX, reelY, hubRadius, 0, 2 * Math.PI);
        ctx.fill();

        ctx.fillStyle = '#404040';
        ctx.beginPath();
        ctx.moveTo(guideRightX, guideBottomY);
        ctx.arc(guideRightX, guideBottomY, guideRightX - guideLeftX, Math.PI, 3 * Math.PI / 2);
        ctx.closePath();
        ctx.fill();

        ctx.strokeStyle = '#FFFFFF';
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.arc(guideRightX, guideBottomY, guideRightX - guideLeftX, Math.PI, 3 * Math.PI / 2);
        ctx.stroke();

        for (let i = 0; i < 6; i++) {
            this.drawSpoke(ctx, w, h, hubRadius, startAng + i * Math.PI / 3);
        }
        ctx.resetTransform();
    }

    private drawHead(ctx: CanvasRenderingContext2D, w: number, h: number) {
        const headLeftX = w * this.HEAD_LEFT_X;
        const headTopY = h * this.HEAD_TOP_Y;
        const headTopY1 = h * this.HEAD_TOP_Y1;
        const headBottomY = h * this.HEAD_BOTTOM_Y;

        ctx.fillStyle = '#c0c0c0';
        ctx.beginPath();
        ctx.moveTo(headLeftX, headTopY1);
        ctx.lineTo(w, headTopY);
        ctx.lineTo(w, headBottomY);
        ctx.lineTo(headLeftX, headBottomY);
        ctx.lineTo(headLeftX, headTopY1);
        ctx.closePath();
        ctx.fill();
    }

    private drawSpoke(ctx: CanvasRenderingContext2D, w: number, h: number, hubRadius: number, angle: number) {
        const reelX = this.REEL_CENTER_X * w;
        const reelY = this.REEL_CENTER_Y * h;

        ctx.fillStyle = '#323250';
        const x = Math.cos(angle);
        const y = Math.sin(angle);
        const x1 = Math.cos(angle - 25 * Math.PI / 180);
        const y1 = Math.sin(angle - 25 * Math.PI / 180)
        const x2 = Math.cos(angle + 25 * Math.PI / 180);
        const y2 = Math.sin(angle + 25 * Math.PI / 180)

        ctx.beginPath();
        ctx.moveTo(reelX - x * hubRadius * 0.1, reelY + y * hubRadius * 0.1);
        ctx.lineTo(reelX + x1 * hubRadius * 0.5, reelY - y1 * hubRadius * 0.5);
        ctx.lineTo(reelX + x * hubRadius, reelY - y * hubRadius);
        ctx.lineTo(reelX + x2 * hubRadius * 0.5, reelY - y2 * hubRadius * 0.5);
        ctx.lineTo(reelX - x * hubRadius * 0.1, reelY + y * hubRadius * 0.1);
        ctx.closePath();
        ctx.fill();
    }
}
