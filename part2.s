.include    "address_map_arm.s" 
.include    "interrupt_ID.s" 

/* ********************************************************************************
 * This program demonstrates use of interrupts with assembly language code.
 * The program responds to interrupts from the pushbutton KEY port in the FPGA.
 *
 * The interrupt service routine for the pushbutton KEYs indicates which KEY has
 * been pressed on the LED display.
 ********************************************************************************/

.section    .vectors, "ax" 

            B       _start                  // reset vector
            B       SERVICE_UND             // undefined instruction vector
            B       SERVICE_SVC             // software interrrupt vector
            B       SERVICE_ABT_INST        // aborted prefetch vector
            B       SERVICE_ABT_DATA        // aborted data vector
.word       0 // unused vector
            B       SERVICE_IRQ             // IRQ interrupt vector
            B       SERVICE_FIQ             // FIQ interrupt vector

.text        
.global     _start 
_start:                                     
/* Set up stack pointers for IRQ and SVC processor modes */
            MOV     R1, #0b11010010         // interrupts masked, MODE = IRQ
            MSR     CPSR_c, R1              // change to IRQ mode
            LDR     SP, =A9_ONCHIP_END - 3  // set IRQ stack to top of A9 onchip memory
/* Change to SVC (supervisor) mode with interrupts disabled */
            MOV     R1, #0b11010011         // interrupts masked, MODE = SVC
            MSR     CPSR, R1                // change to supervisor mode
            LDR     SP, =DDR_END - 3        // set SVC stack to top of DDR3 memory

            BL      CONFIG_GIC              // configure the ARM generic interrupt controller

                                            // write to the pushbutton KEY interrupt mask register
            LDR     R0, =KEY_BASE           // pushbutton KEY base address
            MOV     R1, #0xF               // set interrupt mask bits
            STR     R1, [R0, #0x8]          // interrupt mask register is (base + 8)

                                            // enable IRQ interrupts in the processor
            MOV     R0, #0b01010011         // IRQ unmasked, MODE = SVC
            MSR     CPSR_c, R0              
CONFIG_TIMER:
            LDR     R0, =MPCORE_PRIV_TIMER  // set R0 points to MPCORE_PRIV_TIMER
            LDR     R1, =SWTIME             // set switch time to be 10^8, which is 0.5s
            STR     R1, [R0, #0]            // load TIMER_LOAD be 10^8
            MOV     R1, #7                  // let R1 be 0b111
            STR     R1, [R0, #8]            // load control bit (I A E) be (1 1 1)
            .equ    SWTIME,          0x5F5E100
IDLE:                                       
            B       IDLE                    // main program simply idles

/* Define the exception service routines */

/*--- Undefined instructions --------------------------------------------------*/
SERVICE_UND:                                
            B       SERVICE_UND             

/*--- Software interrupts -----------------------------------------------------*/
SERVICE_SVC:                                
            B       SERVICE_SVC             

/*--- Aborted data reads ------------------------------------------------------*/
SERVICE_ABT_DATA:                           
            B       SERVICE_ABT_DATA        

/*--- Aborted instruction fetch -----------------------------------------------*/
SERVICE_ABT_INST:                           
            B       SERVICE_ABT_INST        

/*--- IRQ ---------------------------------------------------------------------*/
SERVICE_IRQ:                                
            PUSH    {R0-R7, LR}             

/* Read the ICCIAR from the CPU interface */
            LDR     R4, =MPCORE_GIC_CPUIF   
            LDR     R5, [R4, #ICCIAR]       // read from ICCIAR

FPGA_IRQ1_HANDLER:                          
            CMP     R5, #KEYS_IRQ           
UNEXPECTED: BNE     FPGA_IQR2_HANDLER              

            BL      KEY_ISR 
            B       EXIT_IRQ                

FPGA_IQR2_HANDLER:
            CMP     R5, #MPCORE_PRIV_TIMER_IRQ   
TIMER_UNEXPECTED:
            BNE     TIMER_UNEXPECTED        // if not recognized, stop here
            BL      TIMER_ISR

EXIT_IRQ:                                   
/* Write to the End of Interrupt Register (ICCEOIR) */
            STR     R5, [R4, #ICCEOIR]      // write to ICCEOIR

            POP     {R0-R7, LR}             
            SUBS    PC, LR, #4              

/*--- FIQ ---------------------------------------------------------------------*/
SERVICE_FIQ:                                
            B       SERVICE_FIQ             

/*TIMER_ISR*/
TIMER_ISR:
            LDR R0, =number                 // Let R0 be the pointer to glob var number
            LDR R1, =LED_BASE               // Let R1 be the pointer to LED
            LDR R2, [R0]                    // Load current num, initaially 0
            STR R2, [R1]                    // write to LED
            ADD R2, R2, #1                  // increment number by 1
            STR R2, [R0]                    // Write back to number


number:
    .word 0

.end         
