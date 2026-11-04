//
//  PerspectiveCamera+AVFoundation.mm
//  StandardCyborgFusion
//
//  Created by Aaron Thompson on 12/19/18.
//

#import <AVFoundation/AVFoundation.h>
#import <standard_cyborg/util/DataUtils.hpp>
#import <standard_cyborg/math/Mat3x3.hpp>
#import <standard_cyborg/math/Mat3x4.hpp>
#import <standard_cyborg/math/Vec2.hpp>
#import <vector>
#import <stdio.h>
#import <sys/utsname.h>

#import "EigenHelpers.hpp"
#import "GeometryHelpers.hpp"
#import "PerspectiveCamera+AVFoundation.hpp"

using namespace standard_cyborg;

// The physical front-camera sensor orientation is a *hardware property*.
// An image with 16:9 dimensions does not necessarily come from a portrait-
// mounted sensor: the capture preset can crop or scale older iPhone cameras.
// iPhone 17 / iPhone Air models (iPhone18,*) introduced a portrait-mounted
// front sensor. Earlier iPhones (including the iPhone 13 / iPhone14,5)
// have a sideways-mounted front TrueDepth camera.
static bool HasPortraitMountedFrontSensor()
{
    struct utsname info = {};
    if (uname(&info) != 0) { return false; }

    int hardwareGeneration = 0;
    if (sscanf(info.machine, "iPhone%d,", &hardwareGeneration) == 1) {
        return hardwareGeneration >= 18;
    }

    // Preserve the legacy layout on iPads / unidentified devices until
    // their physical sensor orientation has been calibrated.
    return false;
}

static bool UsePortraitFrontSensorMapping()
{
    // Diagnostic override used by *both* TrueDepthFusion and
    // StandardCyborgExample. Set in iOS Settings; restart the app afterward.
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"SCTrueDepthSensorLayout"];
    if ([mode isEqualToString:@"portrait"]) { return true; }
    if ([mode isEqualToString:@"sideways"]) { return false; }
    return HasPortraitMountedFrontSensor();
}

sc3d::PerspectiveCamera PerspectiveCameraFromAVCameraCalibrationData(AVCameraCalibrationData *calibrationData, size_t pixelsWide, size_t pixelsHigh)
{
    NSData *lensDistortionLookupTableData = calibrationData.lensDistortionLookupTable;
    NSData *inverseLensDistortionLookupTableData = calibrationData.inverseLensDistortionLookupTable;
    
    std::vector<float> lensDistortionTable {};
    const float* tableData = (float*)[lensDistortionLookupTableData bytes];
    lensDistortionTable.assign(tableData, tableData + [lensDistortionLookupTableData length] / sizeof(float));

    std::vector<float> inverseLensDistortionTable {};
    const float* inverseTableData = (float*)[inverseLensDistortionLookupTableData bytes];
    inverseLensDistortionTable.assign(inverseTableData, inverseTableData + [inverseLensDistortionLookupTableData length] / sizeof(float));

    sc3d::PerspectiveCamera camera;

    // Determined after length investigation of the effect of focal length on dimensional accuracy and
    // loop closure. There's a fair bit of scatter in the data, so this is certainly not "correct",
    // merely "much, much better than nothing." For more details, see:
    //    https://github.com/StandardCyborg/ScanAnalysis/tree/master/ScanAnalysis/2019-05-09-dimensional-accuracy-calibration
    camera.setFocalLengthScaleFactor(1.019f);

    math::Mat3x4 extrinsicMatrix(toMat3x4(calibrationData.extrinsicMatrix));
    camera.setExtrinsicMatrix(extrinsicMatrix);

    // The extrinsic matrix Apple gives us in calibrationData.extrinsicMatrix doesn't match the
    // coordinate system we otherwise prefer, so we post-multiply by an orientation matrix to
    // produce world space with x to the right, y up, and z toward the user.
    //
    // Earlier iPhone sensors are physically sideways-mounted, even if their
    // *output* / calibration dimensions happen to be 16:9. In 2026 the
    // original aspect-ratio heuristic could select the wrong orientation on
    // iPhone 13 and rotate the resulting point cloud by 90 degrees.
    //
    // Legacy mapping: swap X/Y and invert Z.
    // Portrait-mounted mapping: keep X, invert Y/Z.
    const bool portraitMounted = UsePortraitFrontSensorMapping();

    static dispatch_once_t orientationLogOnce;
    dispatch_once(&orientationLogOnce, ^{
        CGSize dims = calibrationData.intrinsicMatrixReferenceDimensions;
        NSLog(@"[StandardCyborgFusion] TrueDepth sensor layout: %@, intrinsics reference: %.0fx%.0f",
              portraitMounted ? @"portrait-mounted" : @"sideways-mounted", dims.width, dims.height);
    });

    math::Mat3x4 desiredOrientation = portraitMounted
        ? math::Mat3x4({
            1, 0, 0, 0,
            0, -1, 0, 0,
            0, 0, -1, 0
        })
        : math::Mat3x4({
            0, 1, 0, 0,
            1, 0, 0, 0,
            0, 0, -1, 0
        });
    // We construct a baseline extrinsic matrix strictly to nail down our desired output given
    // expected input, with the additional expectation that if the extrinsic matrix returned by
    // Apple changed for some reason, we'd actually want to pick up those changes. That is to say,
    // all of this is constructed to save and use Apple's extrinsic matrix but post-multiply it
    // by our own matrix strictly to achieve the matrix we *want*.
    math::Mat3x4 baselineExtrinsicMatrix = math::Mat3x4::Identity();
    math::Mat3x4 orientationMatrix(desiredOrientation * baselineExtrinsicMatrix.inverse());
    
    camera.setOrientationMatrix(orientationMatrix);
    
    camera.setNominalIntrinsicMatrix(toMat3x3(calibrationData.intrinsicMatrix));
    camera.setIntrinsicMatrixReferenceSize(math::Vec2(calibrationData.intrinsicMatrixReferenceDimensions.width,
                                                           calibrationData.intrinsicMatrixReferenceDimensions.height));
    camera.setLensDistortionLookupTable(lensDistortionTable);
    camera.setInverseLensDistortionLookupTable(inverseLensDistortionTable);
    camera.setLegacyImageSize({(int)pixelsWide, (int)pixelsHigh});
    
    return camera;
}
