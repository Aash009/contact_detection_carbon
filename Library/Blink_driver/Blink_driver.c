/*
 * LedDriver.c
 *
 *  Created on: Mar 30, 2023
 *      Author: rajes
 */

#include "Blink_driver.h"

/**
  * @brief  Post check Function Definition of LED Driver
  * @note   PostCheck_LED() function must be called at main (or some other file) for implementing the post check
  * @param  None
  * @retval None
  */
void PostCheck_LED(void) // Post check function for LED
{
	    HAL_GPIO_WritePin(GREEN_LED_GPIO_Port, GREEN_LED_Pin, GPIO_PIN_RESET);              /// Turn ON green led for post check.                                                                                  /// Update OLED screen with data.
		HAL_Delay(100);                                                                     /// Delay of 100 milli second for next post check.
		HAL_GPIO_WritePin(GREEN_LED_GPIO_Port, GREEN_LED_Pin, GPIO_PIN_SET);                /// Turn OFF green led.
		HAL_GPIO_WritePin(BLUE_LED_GPIO_Port, BLUE_LED_Pin, GPIO_PIN_RESET);                /// Turn ON blue led for next post check.                                                                                   /// Update OLED screen with data.
		HAL_Delay(100);                                                                    /// Delay of 100 milli second for next post check.
		HAL_GPIO_WritePin(BLUE_LED_GPIO_Port, BLUE_LED_Pin, GPIO_PIN_SET);                 /// Turn OFF blue led.
		HAL_GPIO_WritePin(RED_LED_GPIO_Port, RED_LED_Pin, GPIO_PIN_RESET);                /// Turn ON RED led for next post check.                                                                                   /// Update OLED screen with data.                                                                                           /// Delay of 1 second for next post check.
}

