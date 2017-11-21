//
//  ViewController.h
//  BleCarControl
//
//  Created by Manuel Schreiner on 13.02.16.
//  Copyright © 2016 io-expert.com. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>



@interface ViewController : UIViewController
@property (strong, nonatomic) CMMotionManager *motionManager;
- (IBAction)forwardStart:(id)sender;
- (IBAction)backwardStart:(id)sender;
- (IBAction)moveStop:(id)sender;
- (IBAction)forwardLeftStart:(id)sender;
- (IBAction)forwardRightStart:(id)sender;
- (IBAction)backwardLeftStart:(id)sender;
- (IBAction)backwardRightStart:(id)sender;
@property (weak, nonatomic) IBOutlet UIButton *flBtn;
@property (weak, nonatomic) IBOutlet UIButton *blBtn;
@property (weak, nonatomic) IBOutlet UIButton *brBtn;
@property (weak, nonatomic) IBOutlet UIButton *frBtn;

@end

