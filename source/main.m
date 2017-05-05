//
//  main.m
//  class-dump
//
//  Created by EugeneYang on 16/8/22.
//
//

#include <stdio.h>

#include <unistd.h>
#include <getopt.h>
#include <stdlib.h>
#include <mach-o/arch.h>



#define RESTORE_SYMBOL_BASE_VERSION "1.0 (64 bit)"

#ifdef DEBUG
#define RESTORE_SYMBOL_VERSION RESTORE_SYMBOL_BASE_VERSION //" (Debug version compiled " __DATE__ " " __TIME__ ")"
#else
#define RESTORE_SYMBOL_VERSION RESTORE_SYMBOL_BASE_VERSION
#endif

#define RS_OPT_DISABLE_OC_DETECT 1
#define RS_OPT_VERSION 2
#define RS_OPT_REPLACE_RESTRICT 3


NSString *runSystemCommand(NSString * cmd)
{
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath: @"/bin/bash"];
    NSArray *arguments = [NSArray arrayWithObjects: @"-c", cmd, nil];
    [task setArguments: arguments];
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];
    NSFileHandle *file = [pipe fileHandleForReading];
    [task launch];
    NSData *data = [file readDataToEndOfFile];
    return [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
}


void print_usage(void)
{
    fprintf(stderr,
            "\n"
            "restore-symbol %s\n"
            "\n"
            "Usage: restore-symbol -o <output-file> [-j <json-symbol-file>] <mach-o-file>\n"
            "\n"
            "  where options are:\n"
            "        -o <output-file>           New mach-o-file path\n"
            "        --disable-oc-detect        Disable auto detect and add oc method into symbol table,\n"
            "                                   only add symbol in json file\n"
            "        --replace-restrict         New mach-o-file will replace the LC_SEGMENT(__RESTRICT,__restrict)\n"
            "                                   with LC_SEGMENT(__restrict,__restrict) to close dylib inject protection\n"
            "        -j <json-symbol-file>      Json file containing extra symbol info, the key is \"name\",\"address\"\n                                   like this:\n                                   \n"
            "                                        [\n                                         {\n                                          \"name\": \"main\", \n                                          \"address\": \"0xXXXXXX\"\n                                         }, \n                                         {\n                                          \"name\": \"-[XXXX XXXXX]\", \n                                          \"address\": \"0xXXXXXX\"\n                                         },\n                                         .... \n                                        ]\n"
            
            ,
            RESTORE_SYMBOL_VERSION
            );
}



void restore_symbol(NSString * inpath, NSString *outpath, NSString *jsonPath, bool oc_detect_enable, bool replace_restrict);

int main(int argc, char * argv[]) {
    
    
    
    
    bool oc_detect_enable = true;
    bool replace_restrict = false;
    NSString *inpath = nil;
    NSString * outpath = nil;
    NSString *jsonPath = nil;
    
    BOOL shouldPrintVersion = NO;
    
    int ch;
    
    struct option longopts[] = {
        { "disable-oc-detect",       no_argument,       NULL, RS_OPT_DISABLE_OC_DETECT },
        { "output",                  required_argument, NULL, 'o' },
        { "json",                    required_argument, NULL, 'j' },
        { "version",                 no_argument,       NULL, RS_OPT_VERSION },
        { "replace-restrict",        no_argument,       NULL, RS_OPT_REPLACE_RESTRICT },
        
        { NULL,                      0,                 NULL, 0 },
        
    };
    
    
    if (argc == 1) {
        print_usage();
        exit(0);
    }
    
    
    
    while ( (ch = getopt_long(argc, argv, "o:j:", longopts, NULL)) != -1) {
        switch (ch) {
            case 'o':
                outpath = [NSString stringWithUTF8String:optarg];
                break;
            case 'j':
                jsonPath = [NSString stringWithUTF8String:optarg];
                break;
                
            case RS_OPT_VERSION:
                shouldPrintVersion = YES;
                break;
                
            case RS_OPT_DISABLE_OC_DETECT:
                oc_detect_enable = false;
                break;
                
            case RS_OPT_REPLACE_RESTRICT:
                replace_restrict = true;
                break;
            default:
                break;
        }
    }
    
    if (shouldPrintVersion) {
        printf("restore-symbol %s compiled %s\n", RESTORE_SYMBOL_VERSION, __DATE__ " " __TIME__);
        exit(0);
    }
    
    if (optind < argc) {
        inpath = [NSString stringWithUTF8String:argv[optind]];
    }
    
    NSString *infoCommand = [NSString stringWithFormat:@"lipo -info %@",inpath];
    NSString *info = runSystemCommand(infoCommand);
    NSMutableArray *archs = @[].mutableCopy;
    [[info componentsSeparatedByString:@" "] enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj hasPrefix:@"arm"]) {
            [archs addObject:obj];
        }
    }];
    NSString *tempOutpath = outpath == nil ? [inpath stringByAppendingString:@"-o"] : outpath;
    if (archs.count > 1) {
        NSString *tempDir = [[inpath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@".thintemp"];
        [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:NO attributes:nil error:nil];
        NSMutableString *createCommand = @"lipo -create ".mutableCopy;
        for (NSString *arch in archs) {
            NSString *thinMachO = [NSString stringWithFormat:@"%@/%@-%@",tempDir,inpath.lastPathComponent,arch];
            NSString *thinMachOWithSymbol = [NSString stringWithFormat:@"%@-with_symbol",thinMachO];
            NSString *thinCommand = [NSString stringWithFormat:@"lipo %@ -thin %@ -output %@",inpath,arch,thinMachO];
            runSystemCommand(thinCommand);
            restore_symbol(thinMachO, thinMachOWithSymbol, jsonPath, oc_detect_enable, replace_restrict);
            [createCommand appendFormat:@"%@ ",thinMachOWithSymbol];
        }
        [createCommand appendFormat:@"-output %@",tempOutpath];
        runSystemCommand(createCommand);
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
    } else {
        restore_symbol(inpath, tempOutpath, jsonPath, oc_detect_enable, replace_restrict);
    }
    if (outpath == nil) {
        [[NSFileManager defaultManager] removeItemAtPath:inpath error:nil];
        [[NSFileManager defaultManager] moveItemAtPath:tempOutpath toPath:inpath error:nil];
    }
}
