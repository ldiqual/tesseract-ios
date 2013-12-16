//
//  Tesseract.mm
//  Tesseract
//
//  Created by Loïs Di Qual on 24/09/12.
//  Copyright (c) 2012 Loïs Di Qual.
//  Under MIT License. See 'LICENCE' for more informations.
//

#import "Tesseract.h"

#import "baseapi.h"
#import "environ.h"
#import "pix.h"
#import "ocrclass.h"

NSString * const OcrEngineModeTesseractOnly = @"OcrEngineModeTesseractOnly";
NSString * const OcrEngineModeCubeOnly = @"OcrEngineModeCubeOnly";
NSString * const OcrEngineModeTesseractCubeCombined = @"OcrEngineModeTesseractCubeCombined";
NSString * const OcrEngineModeDefault = @"OcrEngineModeDefault";

namespace tesseract {
    class TessBaseAPI;
};

@interface Tesseract () {
    tesseract::TessBaseAPI* _tesseract;
    uint32_t* _pixels;
    bool _setOnlyNonDebugParams;
    tesseract::OcrEngineMode _ocrEngineMode;
    
    NSArray* _configFilenames;
}

@end

@implementation Tesseract

@synthesize tessDelegate;

+ (NSString *)version {
    return [NSString stringWithFormat:@"%s", tesseract::TessBaseAPI::Version()];
}

- (id)initWithDataPath:(NSString *)dataPath
              language:(NSString *)language
         ocrEngineMode:(NSString *)mode
       configFilenames:(NSArray*)configFilenames
             variables:(NSDictionary*)variables
 setOnlyNonDebugParams:(BOOL)setOnlyNonDebugParams {
    self = [super init];
    if (self) {
        _dataPath = dataPath;
        _language = language;
        
        if (mode) {
            if ([mode isEqualToString:OcrEngineModeTesseractOnly]) {
                _ocrEngineMode = tesseract::OEM_TESSERACT_ONLY;
            } else if ([mode isEqualToString:OcrEngineModeCubeOnly]) {
                _ocrEngineMode = tesseract::OEM_CUBE_ONLY;
            } else if ([mode isEqualToString:OcrEngineModeTesseractCubeCombined]) {
                _ocrEngineMode = tesseract::OEM_TESSERACT_CUBE_COMBINED;
            } else {
                _ocrEngineMode = tesseract::OEM_DEFAULT;
            }
        } else {
            _ocrEngineMode = tesseract::OEM_DEFAULT;
        }
        
        _configFilenames = configFilenames;
        
        if (variables) {
            _variables = [variables mutableCopyWithZone:NULL];
        } else {
            _variables = [[NSMutableDictionary alloc] init];
        }
        
        if (setOnlyNonDebugParams) {
            _setOnlyNonDebugParams = true;
        } else {
            _setOnlyNonDebugParams = false;
        }
        
        [self copyDataToDocumentsDirectory];
        _tesseract = new tesseract::TessBaseAPI();
        
        BOOL success = [self initEngine];
        if (!success) {
            return NO;
        }
    }
    return self;
}

- (id)initWithDataPath:(NSString *)dataPath language:(NSString *)language {
    return [self initWithDataPath:dataPath
                         language:language
                    ocrEngineMode:OcrEngineModeDefault
                  configFilenames:nil
                        variables:nil
            setOnlyNonDebugParams:NO];
}

- (BOOL)initEngine {
    char **configs = NULL;
    int configs_size = 0;
    GenericVector<STRING> keys;
    GenericVector<STRING> values;
    
    if (_configFilenames && _configFilenames.count > 0) {
        configs = (char**) malloc(_configFilenames.count * sizeof(char*));
        for (; configs_size < _configFilenames.count; configs_size++) {
            configs[configs_size] = (char*) malloc((((NSString*)(_configFilenames[configs_size])).length + 1) * sizeof(char));
            strncpy(configs[configs_size], [_configFilenames[configs_size] UTF8String], ((NSString*)(_configFilenames[configs_size])).length + 1);
        }
    }
    
    for (NSString* key in _variables) {
        keys.push_back([key UTF8String]);
        values.push_back([_variables[key] UTF8String]);
    }
    
    int returnCode = _tesseract->Init(_dataPath ? [_dataPath UTF8String] : NULL,
                                      _language ? [_language UTF8String] : NULL,
                                      _ocrEngineMode,
                                      configs,
                                      configs_size,
                                      &keys,
                                      &values,
                                      _setOnlyNonDebugParams);
    if (configs) {
        for (int filenameIndex = 0; filenameIndex < configs_size; filenameIndex++) {
            free(configs[filenameIndex]);
        }
        free(configs);
    }
    
    return (returnCode == 0) ? YES : NO;
}

- (void)copyDataToDocumentsDirectory {
    
    // Useful paths
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentPath = ([documentPaths count] > 0) ? [documentPaths objectAtIndex:0] : nil;
    NSString *dataPath = [documentPath stringByAppendingPathComponent:_dataPath];
    
    // Copy data in Doc Directory
    if (![fileManager fileExistsAtPath:dataPath]) {
        NSString *bundlePath = [[NSBundle bundleForClass:[self class]] bundlePath];
        NSString *tessdataPath = [bundlePath stringByAppendingPathComponent:_dataPath];
        if (tessdataPath) {
            [fileManager createDirectoryAtPath:documentPath withIntermediateDirectories:YES attributes:nil error:NULL];
            [fileManager copyItemAtPath:tessdataPath toPath:dataPath error:nil];
        }
    }
    
    setenv("TESSDATA_PREFIX", [[documentPath stringByAppendingString:@"/"] UTF8String], 1);
}

- (void)setVariableValue:(NSString *)value forKey:(NSString *)key {
    /*
     * Example:
     * _tesseract->SetVariable("tessedit_char_whitelist", "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ");
     * _tesseract->SetVariable("language_model_penalty_non_freq_dict_word", "0");
     * _tesseract->SetVariable("language_model_penalty_non_dict_word ", "0");
     */
    
    [_variables setValue:value forKey:key];
    _tesseract->SetVariable([key UTF8String], [value UTF8String]);
}

- (void)loadVariables {
    for (NSString* key in _variables) {
        NSString* value = [_variables objectForKey:key];
        _tesseract->SetVariable([key UTF8String], [value UTF8String]);
    }
}

- (BOOL)setLanguage:(NSString *)language {
    _language = language;
    int returnCode = [self initEngine];
    if (returnCode != 0) return NO;
    
    /*
     * "WARNING: On changing languages, all Tesseract parameters
     * are reset back to their default values."
     */
    [self loadVariables];
    return YES;
}

- (BOOL)recognize {
    int returnCode = _tesseract->Recognize(NULL);
    return (returnCode == 0) ? YES : NO;
}
  
- (BOOL)recognizeWithProgressUpdate {

    _progress = 0;
    ETEXT_DESC *monitor = new ETEXT_DESC;

    void (^progressBlock)(void) = ^void {
        if (monitor->progress > _progress) {
            _progress = monitor->progress;
            [self.tessDelegate progressUpdate:_progress];
        }
    };
  
    dispatch_queue_t backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t timer = createDispatchTimer(1, 0, backgroundQueue, progressBlock);
  
    int returnCode = _tesseract->Recognize(monitor);

    if(_progress < 100) {
        _progress = 100;
        [self.tessDelegate progressUpdate:_progress];
    }
  
    dispatch_release(timer);
    delete monitor;
  
    return (returnCode == 0) ? YES : NO;
}

- (NSString *)recognizedText {
    char* utf8Text = _tesseract->GetUTF8Text();
    return [NSString stringWithUTF8String:utf8Text];
}

- (void)clear
{
    free(_pixels);
    _tesseract->Clear();
    _tesseract->End();
}

- (void)setImage:(UIImage *)image
{
    free(_pixels);
    
    CGSize size = [image size];
    int width = size.width;
    int height = size.height;
	
	if (width <= 0 || height <= 0) {
		return;
    }
	
    _pixels = (uint32_t *) malloc(width * height * sizeof(uint32_t));
    
    // Clear the pixels so any transparency is preserved
    memset(_pixels, 0, width * height * sizeof(uint32_t));
	
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	
    // Create a context with RGBA _pixels
    CGContextRef context = CGBitmapContextCreate(_pixels, width, height, 8, width * sizeof(uint32_t), colorSpace,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedLast);
	
    // Paint the bitmap to our context which will fill in the _pixels array
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), [image CGImage]);
	
	// We're done with the context and color space
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    _tesseract->SetImage((const unsigned char *) _pixels, width, height, sizeof(uint32_t), width * sizeof(uint32_t));
}

#pragma mark - progress update

dispatch_source_t createDispatchTimer(uint64_t interval,
                                      uint64_t leeway,
                                      dispatch_queue_t queue,
                                      dispatch_block_t block)
{
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                   0, 0, queue);
    if (timer) {
        dispatch_source_set_timer(timer, dispatch_walltime(NULL, 0), interval, leeway);
        dispatch_source_set_event_handler(timer, block);
        dispatch_resume(timer);
    }
  
    return timer;
}

@end
