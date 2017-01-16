//
//  main.m
//  TeCPDFMaker
//
//  Created by Himanshu Verma on 03/10/16.
//  Copyright © 2016 human-ist.unifr.ch. All rights reserved.
//

//int main(int argc, const char * argv[]) {
//    @autoreleasepool {
//        // insert code here...
//        NSLog(@"Hello, World!");
//    }
//    return 0;
//}

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>

#define NSPrint(FORMAT, ...) printf("%s\n", [[NSString stringWithFormat:FORMAT, ##__VA_ARGS__] UTF8String]);
#define NSErr(FORMAT, ...) fprintf(stderr, "%s\n", [[NSString stringWithFormat:FORMAT, ##__VA_ARGS__] UTF8String]);
#define MM2D(x) ((x)*72.0/25.4)
#define D2MM(x) ((x)*25.4/72.0)
void PreparePDF(NSURL *inputURL, NSURL *outputURL, NSInteger startPage);

BOOL CheckDocumentDimensions(CGPDFDocumentRef document, CGRect *dimensions);
void OverlayPageNumber(CGContextRef context, CGRect dimensions, NSUInteger pageNumber);
void OverlayDebug(CGContextRef context, CGRect dimensions, BOOL isFirstPage);
void OverlaySessionAndConf(CGContextRef context, CGRect dimensions, NSString *session, NSString *conf);
void OverlayDOI(CGContextRef context, CGRect dimensions, NSString *doi, BOOL copyrightDefault);

@interface PPImageOverlay : NSObject
{
    CGPDFDocumentRef document;
    CGPDFPageRef page;
}
+(id)overlayWithURL:(NSURL *)URL;
-(id)initWithURL:(NSURL *)overlayURL;
@property (readonly, nonatomic) CGRect dimensions;
@property (readonly, nonatomic) CGPDFPageRef PDFPage;
-(void)drawAtPoint:(CGPoint)position onContext:(CGContextRef)context;
@end

@interface NSURL (PreparePDF)
+(NSURL *)fileURLWithRelativePathToExecutable:(NSString *)path;
@end

#pragma mark Command line interaction

const char *PreparePDFProgramName;

void PrintUsage() {
    NSErr(@"Prepare a PDF file for inclusion in the proceedings and print the next available page number to the standard output.");
    NSErr(@"Usage: %@ -input <file.pdf> -output <file.pdf> [options]", @(PreparePDFProgramName));
    NSErr(@"Options:");
    NSErr(@"-startpage <number>\n\tStart from given page number (0 for no page numbers)");
    NSErr(@"-title <title>\n\tSet the title in PDF metadata");
    NSErr(@"-author <author>\n\tSet the authors in PDF metadata (comma-separated)");
    NSErr(@"-session <text>\n\tAdd the name of the session");
    NSErr(@"-conf <text>\n\tAdd the name of the conference");
}

int main(int argc, const char * argv[])
{
    PreparePDFProgramName = argv[0];
    
    @autoreleasepool {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *infile = [defaults stringForKey:@"input"];
        NSString *outfile = [defaults stringForKey:@"output"];
        
        if(!infile || !outfile) {
            PrintUsage();
            return 64;
        }
        
        //BOOL debug = [defaults boolForKey:@"debug"];
        NSInteger startPage = [defaults integerForKey:@"startpage"];
        
        PreparePDF([NSURL fileURLWithPath:infile], [NSURL fileURLWithPath:outfile], startPage);
    }
    return 0;
}

#pragma mark Main processing

void PreparePDF(NSURL *inputURL, NSURL *outputURL, NSInteger startPage)
{
    // Load the overlays
    
    NSString *errorQualifier = @"Error";
    
    // Load the input document
    CGPDFDocumentRef inputDocument = CGPDFDocumentCreateWithURL((__bridge CFURLRef)(inputURL));
    
    if(!inputDocument) {
        NSErr(@"Error: The input file cannot be open: %@.", [inputURL path]);
        exit(1);
    }
    
    // Check the dimensions
    CGRect expectedDimensions = CGRectMake(0, 0, MM2D(297), MM2D(210));
    CGRect dimensions = expectedDimensions;
    BOOL dimensionsOK = CheckDocumentDimensions(inputDocument, &dimensions);
    if(!dimensionsOK) {
        NSErr(@"Warning: The input document does not have the expected dimensions: %@ (expected: %@).", NSStringFromRect(NSRectFromCGRect(dimensions)), NSStringFromRect(NSRectFromCGRect(expectedDimensions)));
    }
    
    // Prepare the overlay positions
    
    // Set the output document metadata
    NSMutableDictionary *outputDocumentMetadata = [NSMutableDictionary dictionary];
    NSString *title = [[NSUserDefaults standardUserDefaults] stringForKey:@"title"];
    if(title) {
        [outputDocumentMetadata setObject:title forKey:(id)kCGPDFContextTitle];
    }
    NSString *author = [[NSUserDefaults standardUserDefaults] stringForKey:@"author"];
    if(author) {
        [outputDocumentMetadata setObject:author forKey:(id)kCGPDFContextAuthor];
    }
    
    CGContextRef context = CGPDFContextCreateWithURL((__bridge CFURLRef)(outputURL), &dimensions, (__bridge CFDictionaryRef)(outputDocumentMetadata));
    
    if(!context) {
        NSErr(@"Error: The output file could not be written: %@.", [outputURL path]);
    }
    
    NSString *session = [[NSUserDefaults standardUserDefaults] stringForKey:@"session"];
    NSString *conf = [[NSUserDefaults standardUserDefaults] stringForKey:@"conf"];
    
    NSUInteger pageCount = CGPDFDocumentGetNumberOfPages(inputDocument);
    for(NSUInteger i=0; i<pageCount; ++i) {
        CGPDFContextBeginPage(context, NULL);
        
        NSUInteger page = i + 1;
        
        // First, draw the page from the input document
        CGPDFPageRef inputPage = CGPDFDocumentGetPage(inputDocument, page);
        CGContextDrawPDFPage(context, inputPage);
        
        // Then, superimpose some content
        if(startPage > 0) {
            OverlayPageNumber(context, dimensions, startPage + i);
        }
        
        OverlaySessionAndConf(context, dimensions, session, conf);
        
        CGPDFContextEndPage(context);
    }
    CGPDFContextClose(context);
    
    CFRelease(context);
    CFRelease(inputDocument);
    
    NSPrint(@"%lu", startPage + pageCount);
}

#pragma mark Checking

BOOL CheckDocumentDimensions(CGPDFDocumentRef document, CGRect *dimensions) {
    NSUInteger pageCount = CGPDFDocumentGetNumberOfPages(document);
    for(NSUInteger i=0; i<pageCount; ++i) {
        CGPDFPageRef page = CGPDFDocumentGetPage(document, i + 1);
        CGRect pageBox = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
        if(!CGRectEqualToRect(CGRectIntegral(pageBox), CGRectIntegral(*dimensions))) {
            *dimensions = pageBox;
            return NO;
        }
    }
    return YES;
}

#pragma mark Loading image overlays

@implementation PPImageOverlay
@synthesize dimensions;
@synthesize PDFPage = page;

+(id)overlayWithURL:(NSURL *)URL
{
    return [[[self alloc] initWithURL:URL] autorelease];
}

-(id)initWithURL:(NSURL *)overlayURL
{
    self = [super init];
    if(self) {
        document = CGPDFDocumentCreateWithURL((__bridge CFURLRef)(overlayURL));
        if(!document) {
            [self release];
            return nil;
        }
        page = CGPDFDocumentGetPage(document, 1);
        dimensions = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
    }
    return self;
}

-(void)dealloc
{
    if(document) {
        CFRelease(document);
    }
    [super dealloc];
}

-(void)drawAtPoint:(CGPoint)position onContext:(CGContextRef)context
{
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, position.x, position.y);
    CGContextDrawPDFPage(context, page);
    CGContextRestoreGState(context);
}

@end

#pragma mark Overlaying

void OverlaySessionAndConf(CGContextRef context, CGRect dimensions, NSString *session, NSString *conf)
{
    if (conf == nil) {
        conf = @"25-28 oct. 2016, Fribourg, Suisse";
    }
    NSLog(@"  -----> %@  &&  %@", session, conf);
    NSDictionary *fontAttributes =
    [NSDictionary dictionaryWithObjectsAndKeys:
     @"Verdana", (NSString *)kCTFontFamilyNameAttribute,
     @"Normal", (NSString *)kCTFontStyleNameAttribute,
     [NSNumber numberWithFloat:10.0],
     (NSString *)kCTFontSizeAttribute,
     nil];
    
    // Create a descriptor.
    CTFontDescriptorRef descriptor =
    CTFontDescriptorCreateWithAttributes((CFDictionaryRef)fontAttributes);
    
    // Create a font using the descriptor.
    CTFontRef font = CTFontCreateWithFontDescriptor(descriptor, 0.0, NULL);
    CFRelease(descriptor);
    
    // Initialize the string, font, and context
    
    CFStringRef keys[] = { kCTFontAttributeName };
    CFTypeRef values[] = { font };
    
    CFDictionaryRef attributes =
    CFDictionaryCreate(kCFAllocatorDefault, (const void**)&keys,
                       (const void**)&values, sizeof(keys) / sizeof(keys[0]),
                       &kCFTypeDictionaryKeyCallBacks,
                       &kCFTypeDictionaryValueCallBacks);
    
    // Session Name
    NSAttributedString *sessionAS = [[NSAttributedString alloc] initWithString:session attributes:(NSDictionary *)attributes];
    CTLineRef sessionLine = CTLineCreateWithAttributedString((CFAttributedStringRef)sessionAS);
    CGContextSetTextPosition(context, MM2D(19), dimensions.size.height - MM2D(20));
    CTLineDraw(sessionLine, context);
    CFRelease(sessionLine);
    [sessionAS release];
    
    // Conference Name
    NSAttributedString *confAS = [[NSAttributedString alloc] initWithString:conf attributes:(NSDictionary *)attributes];
    CTLineRef confLine = CTLineCreateWithAttributedString((CFAttributedStringRef)confAS);
    CGContextSetTextPosition(context, dimensions.size.width - MM2D(70), dimensions.size.height - MM2D(20));
    CTLineDraw(confLine, context);
    CFRelease(confLine);
    [confAS release];
}

void OverlayPageNumber(CGContextRef context, CGRect dimensions, NSUInteger pageNumber)
{
    // Prepare text
    NSString *pageText = [NSString stringWithFormat:@"%lu", pageNumber];
    const char *pageUTF8String = [pageText UTF8String];
    NSUInteger pageTextLength = [pageText length];
    
    // Set text attributes
    //CGContextSelectFont(context, "Source Sans Pro", 15, kCGEncodingMacRoman);
    CGContextSelectFont(context, "Times", 10, kCGEncodingMacRoman);
    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextSetRGBStrokeColor(context, 0, 0, 0, 1);
    
    // Get text metrics
    CGContextSetTextDrawingMode(context, kCGTextInvisible);
    //CGFloat x1 = CGContextGetTextPosition(context).x;
    CGContextShowText(context, pageUTF8String, pageTextLength);
    //CGFloat x2 = CGContextGetTextPosition(context).x;
    CGContextSetTextDrawingMode(context, kCGTextFill);
    //CGFloat pageTextWidth = x2 - x1;
    
    // Draw the text at the appropriate position
    //CGContextShowTextAtPoint(context, dimensions.origin.x + dimensions.size.width * 0.5 - pageTextWidth * 0.5, 30, pageUTF8String, pageTextLength);
    CGContextShowTextAtPoint(context, dimensions.size.width - MM2D(23), 35, pageUTF8String, pageTextLength);
}

void OverlayDOI(CGContextRef context, CGRect dimensions, NSString *doi, BOOL copyrightDefault)
{
    // Prepare text
    const char *doiString = [doi UTF8String];
    NSUInteger doiLength = [doi length];
    
    // Set text attributes
    CGContextSelectFont(context, "Times", 8, kCGEncodingMacRoman);
    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextSetRGBStrokeColor(context, 0, 0, 0, 1);
    
    // Draw the text at the appropriate position
    if (copyrightDefault) {
        CGContextShowTextAtPoint(context, dimensions.origin.x + MM2D(20), dimensions.origin.y + MM2D(29 +10)   , doiString, doiLength);
    } else {
        CGContextShowTextAtPoint(context, dimensions.origin.x + MM2D(20.5), dimensions.origin.y + MM2D(29 -2)   , doiString, doiLength);
    }
}

void OverlayDebug(CGContextRef context, CGRect dimensions, BOOL isFirstPage)
{
    CGContextSetRGBStrokeColor(context, 1, 0, 0, 1);
    CGContextStrokeRect(context, CGRectMake(MM2D(20), MM2D(29), MM2D(81), MM2D(240)));
    CGContextStrokeRect(context, CGRectMake(MM2D(20 + 81 + 8), MM2D(29), MM2D(81), MM2D(240)));
    if(isFirstPage) {
        CGContextStrokeRect(context, CGRectMake(MM2D(20), MM2D(29 + 240 - 60), MM2D(170), MM2D(60)));
    }
}

#pragma mark URLs

@implementation NSURL (PreparePDF)

+(NSURL *)fileURLWithRelativePathToExecutable:(NSString *)path
{
    return [NSURL fileURLWithPath:[[[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:path]];
}

@end
