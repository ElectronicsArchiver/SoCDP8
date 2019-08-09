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
#ifndef SRC_HAL_ZYNQ_ZYNQHAL_H_
#define SRC_HAL_ZYNQ_ZYNQHAL_H_

#include "src/hal/HAL.h"

namespace hal {

class ZynqHAL: public HAL {
public:
    void setup() override;
    void setIOInterruptHandler(const InterruptHandler &handler) override;

    void pokeMem(uint16_t addr, uint16_t value) override;
    uint16_t peekMem(uint16_t addr) override;

private:
    InterruptHandler ioIRQFunc;

    void setupInterrupts();

    static void ioInterruptHandler(void *data);
};

} // namespace hal

#endif /* SRC_HAL_ZYNQ_ZYNQHAL_H_ */