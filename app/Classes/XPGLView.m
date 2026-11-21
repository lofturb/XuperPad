#import "XPGLView.h"

#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <QuartzCore/QuartzCore.h>

static NSString *const XPGLVertexShader =
  @"attribute vec2 aPosition;\n"
  @"attribute vec2 aTexCoord;\n"
  @"varying vec2 vTexCoord;\n"
  @"void main() {\n"
  @"gl_Position = vec4(aPosition, 0.0, 1.0);\n"
  @"vTexCoord = aTexCoord;\n"
  @"}\n";

static NSString *const XPGLFragmentShader =
  @"#ifdef GL_FRAGMENT_PRECISION_HIGH\n"
  @"precision highp float;\n"
  @"#else\n"
  @"precision mediump float;\n"
  @"#endif\n"
  @"varying vec2 vTexCoord;\n"
  @"uniform sampler2D uLuma;\n"
  @"uniform sampler2D uChromaU;\n"
  @"uniform sampler2D uChromaV;\n"
  @"uniform float uYuv;\n"
  @"void main() {\n"
  @"if (uYuv > 0.5) {\n"
  @"  float y = texture2D(uLuma, vTexCoord).r;\n"
  @"  float u = texture2D(uChromaU, vTexCoord).r;\n"
  @"  float v = texture2D(uChromaV, vTexCoord).r;\n"
  @"  y = 1.1643 * (y - 0.0625);\n"
  @"  u = u - 0.5;\n"
  @"  v = v - 0.5;\n"
  @"  float r = y + 1.5958 * v;\n"
  @"  float g = y - 0.39173 * u - 0.81290 * v;\n"
  @"  float b = y + 2.017 * u;\n"
  @"  gl_FragColor = vec4(clamp(r, 0.0, 1.0), clamp(g, 0.0, 1.0), clamp(b, 0.0, 1.0), 1.0);\n"
  @"} else {\n"
  @"  gl_FragColor = texture2D(uLuma, vTexCoord);\n"
  @"}\n"
  @"}\n";

@interface XPGLView () {
  EAGLContext *glContext;
  GLuint shaderProgram;
  GLuint rgbTexture;
  GLuint lumaTexture;
  GLuint chromaUTexture;
  GLuint chromaVTexture;
  GLuint drawFramebuffer;
  GLuint colorRenderbuffer;
  GLint positionAttribute;
  GLint texCoordAttribute;
  GLint lumaUniform;
  GLint chromaUUniform;
  GLint chromaVUniform;
  GLint yuvUniform;
  GLint textureWidth;
  GLint textureHeight;
  GLint lumaTextureWidth;
  GLint lumaTextureHeight;
  GLint chromaTextureWidth;
  GLint chromaTextureHeight;
  GLint drawableWidth;
  GLint drawableHeight;
  XPVideoFrameData *frameData;
  int framePixelWidth;
  int framePixelHeight;
  CADisplayLink *displayLink;
  BOOL programReady;
  BOOL needsUpload;
}

- (void)drawFrame;
- (void)setupFramebuffer;
- (BOOL)setupProgram;
- (BOOL)compileShader:(NSString *)source type:(GLenum)type output:(GLuint *)shader;
- (void)drawQuadUsingYuv:(BOOL)useYuv;
- (void)uploadRGB:(NSData *)data width:(int)width height:(int)height;
- (void)uploadLuma:(XPVideoFrameData *)frame;
- (void)uploadChroma:(XPVideoFrameData *)data;

@end

@implementation XPGLView

+ (Class)layerClass
{
  return [CAEAGLLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self != nil) {
    self.opaque = YES;
    self.backgroundColor = [UIColor blackColor];
    self.contentScaleFactor = 1.0f;
    framePixelWidth = 0;
    framePixelHeight = 0;
    textureWidth = 0;
    textureHeight = 0;
    lumaTextureWidth = 0;
    lumaTextureHeight = 0;
    chromaTextureWidth = 0;
    chromaTextureHeight = 0;
    drawableWidth = 0;
    drawableHeight = 0;
    programReady = NO;
    needsUpload = NO;

    EAGLContext *context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (context != nil) {
      CAEAGLLayer *layer = (CAEAGLLayer *)self.layer;
      layer.opaque = YES;
      @try {
        [layer setValue:context forKey:@"eaglContext"];
      } @catch (NSException *exception) {
      }
      glContext = context;
    }
  }
  return self;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  [self setupFramebuffer];
}

- (void)didMoveToWindow
{
  [super didMoveToWindow];
  if (self.window != nil) {
    if (displayLink == nil) {
      displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(drawFrame)];
      [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
  } else if (displayLink != nil) {
    [displayLink invalidate];
    displayLink = nil;
  }
}

- (void)displayFrame:(XPVideoFrameData *)frame
{
  if (frame == nil) {
    return;
  }
  if (frame.directUpload) {
    if (frame.width <= 0 || frame.height <= 0 ||
        frame.chromaWidth <= 0 || frame.chromaHeight <= 0 ||
        frame.lumaPointer == NULL || frame.chromaUPointer == NULL ||
        frame.chromaVPointer == NULL ||
        frame.lumaStride != frame.width ||
        frame.chromaStride != frame.chromaWidth) {
      return;
    }
  } else if (frame.luma != nil && frame.chromaU != nil && frame.chromaV != nil) {
    if (frame.width <= 0 || frame.height <= 0 ||
        frame.chromaWidth <= 0 || frame.chromaHeight <= 0) {
      return;
    }
  } else if (frame.rgb != nil) {
    if (frame.width <= 0 || frame.height <= 0 ||
        frame.rgb.length < (NSUInteger)(frame.width * frame.height * 3)) {
      return;
    }
  } else {
    return;
  }
  frameData = frame;
  framePixelWidth = frame.width;
  framePixelHeight = frame.height;
  needsUpload = YES;
}

- (void)clearFrame
{
  frameData = nil;
  framePixelWidth = 0;
  framePixelHeight = 0;
  needsUpload = NO;
}

- (void)drawFrame
{
  EAGLContext *context = glContext;
  if (context == nil) {
    return;
  }
  [EAGLContext setCurrentContext:context];
  if (drawableWidth <= 0 || drawableHeight <= 0) {
    return;
  }
  glViewport(0, 0, drawableWidth, drawableHeight);
  glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);
  XPVideoFrameData *data = frameData;
  if (data != nil && programReady && framePixelWidth > 0 && framePixelHeight > 0) {
    BOOL useYuv = data.directUpload ||
                  (data.luma != nil && data.chromaU != nil && data.chromaV != nil);
    if (needsUpload) {
      if (useYuv) {
        [self uploadLuma:data];
        [self uploadChroma:data];
      } else if (data.rgb != nil) {
        [self uploadRGB:data.rgb width:framePixelWidth height:framePixelHeight];
      }
      needsUpload = NO;
    }
    [self drawQuadUsingYuv:useYuv];
  }
  glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
  [context presentRenderbuffer:GL_RENDERBUFFER];
}

- (void)uploadRGB:(NSData *)data width:(int)width height:(int)height
{
  glBindTexture(GL_TEXTURE_2D, rgbTexture);
  if (textureWidth != width || textureHeight != height) {
    glTexImage2D(GL_TEXTURE_2D,
                 0,
                 GL_RGB,
                 width,
                 height,
                 0,
                 GL_RGB,
                 GL_UNSIGNED_BYTE,
                 NULL);
    textureWidth = width;
    textureHeight = height;
  }
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glTexSubImage2D(GL_TEXTURE_2D,
                  0,
                  0,
                  0,
                  width,
                  height,
                  GL_RGB,
                  GL_UNSIGNED_BYTE,
                  data.bytes);
}

- (void)uploadLuma:(XPVideoFrameData *)frame
{
  int width = frame.width;
  int height = frame.height;
  const void *bytes = frame.directUpload ? frame.lumaPointer : frame.luma.bytes;
  if (bytes == NULL || width <= 0 || height <= 0) {
    return;
  }
  glBindTexture(GL_TEXTURE_2D, lumaTexture);
  if (lumaTextureWidth != width || lumaTextureHeight != height) {
    glTexImage2D(GL_TEXTURE_2D,
                 0,
                 GL_LUMINANCE,
                 width,
                 height,
                 0,
                 GL_LUMINANCE,
                 GL_UNSIGNED_BYTE,
                 NULL);
    lumaTextureWidth = width;
    lumaTextureHeight = height;
  }
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glTexSubImage2D(GL_TEXTURE_2D,
                  0,
                  0,
                  0,
                  width,
                  height,
                  GL_LUMINANCE,
                  GL_UNSIGNED_BYTE,
                  bytes);
}

- (void)uploadChroma:(XPVideoFrameData *)data
{
  const void *uBytes = data.directUpload ? data.chromaUPointer : data.chromaU.bytes;
  const void *vBytes = data.directUpload ? data.chromaVPointer : data.chromaV.bytes;
  if (uBytes == NULL || vBytes == NULL) {
    return;
  }
  if (chromaTextureWidth != data.chromaWidth || chromaTextureHeight != data.chromaHeight) {
    glBindTexture(GL_TEXTURE_2D, chromaUTexture);
    glTexImage2D(GL_TEXTURE_2D,
                 0,
                 GL_LUMINANCE,
                 data.chromaWidth,
                 data.chromaHeight,
                 0,
                 GL_LUMINANCE,
                 GL_UNSIGNED_BYTE,
                 NULL);
    glBindTexture(GL_TEXTURE_2D, chromaVTexture);
    glTexImage2D(GL_TEXTURE_2D,
                 0,
                 GL_LUMINANCE,
                 data.chromaWidth,
                 data.chromaHeight,
                 0,
                 GL_LUMINANCE,
                 GL_UNSIGNED_BYTE,
                 NULL);
    chromaTextureWidth = data.chromaWidth;
    chromaTextureHeight = data.chromaHeight;
  }
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glBindTexture(GL_TEXTURE_2D, chromaUTexture);
  glTexSubImage2D(GL_TEXTURE_2D,
                  0,
                  0,
                  0,
                  data.chromaWidth,
                  data.chromaHeight,
                  GL_LUMINANCE,
                  GL_UNSIGNED_BYTE,
                  uBytes);
  glBindTexture(GL_TEXTURE_2D, chromaVTexture);
  glTexSubImage2D(GL_TEXTURE_2D,
                  0,
                  0,
                  0,
                  data.chromaWidth,
                  data.chromaHeight,
                  GL_LUMINANCE,
                  GL_UNSIGNED_BYTE,
                  vBytes);
}

- (void)drawQuadUsingYuv:(BOOL)useYuv
{
  if (drawableWidth <= 0 || drawableHeight <= 0) {
    return;
  }
  double videoAspect = (double)framePixelWidth / (double)framePixelHeight;
  double viewAspect = (double)drawableWidth / (double)drawableHeight;
  double halfWidth = 1.0;
  double halfHeight = 1.0;
  if (videoAspect > viewAspect) {
    halfHeight = viewAspect / videoAspect;
  } else {
    halfWidth = videoAspect / viewAspect;
  }
  GLfloat vertices[8] = {
    (GLfloat)(-halfWidth), (GLfloat)(halfHeight),
    (GLfloat)(halfWidth), (GLfloat)(halfHeight),
    (GLfloat)(-halfWidth), (GLfloat)(-halfHeight),
    (GLfloat)(halfWidth), (GLfloat)(-halfHeight)
  };
  GLfloat coordinates[8] = {
    0.0f, 0.0f,
    1.0f, 0.0f,
    0.0f, 1.0f,
    1.0f, 1.0f
  };
  glUseProgram(shaderProgram);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, useYuv ? lumaTexture : rgbTexture);
  glUniform1i(lumaUniform, 0);
  glActiveTexture(GL_TEXTURE1);
  glBindTexture(GL_TEXTURE_2D, chromaUTexture);
  glUniform1i(chromaUUniform, 1);
  glActiveTexture(GL_TEXTURE2);
  glBindTexture(GL_TEXTURE_2D, chromaVTexture);
  glUniform1i(chromaVUniform, 2);
  glActiveTexture(GL_TEXTURE0);
  glUniform1f(yuvUniform, useYuv ? 1.0f : 0.0f);
  glEnableVertexAttribArray((GLuint)positionAttribute);
  glVertexAttribPointer((GLuint)positionAttribute, 2, GL_FLOAT, GL_FALSE, 0, vertices);
  glEnableVertexAttribArray((GLuint)texCoordAttribute);
  glVertexAttribPointer((GLuint)texCoordAttribute, 2, GL_FLOAT, GL_FALSE, 0, coordinates);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  glDisableVertexAttribArray((GLuint)positionAttribute);
  glDisableVertexAttribArray((GLuint)texCoordAttribute);
}

- (void)setupFramebuffer
{
  EAGLContext *context = glContext;
  if (context == nil) {
    return;
  }
  [EAGLContext setCurrentContext:context];
  if (drawFramebuffer != 0) {
    glDeleteFramebuffers(1, &drawFramebuffer);
    drawFramebuffer = 0;
  }
  if (colorRenderbuffer != 0) {
    glDeleteRenderbuffers(1, &colorRenderbuffer);
    colorRenderbuffer = 0;
  }
  CGSize size = self.bounds.size;
  if (size.width > 0.0f && size.height > 0.0f) {
    glGenFramebuffers(1, &drawFramebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, drawFramebuffer);
    glGenRenderbuffers(1, &colorRenderbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
    glFramebufferRenderbuffer(GL_FRAMEBUFFER,
                              GL_COLOR_ATTACHMENT0,
                              GL_RENDERBUFFER,
                              colorRenderbuffer);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &drawableWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &drawableHeight);
  }
  if (!programReady) {
    programReady = [self setupProgram];
  }
  if (programReady && rgbTexture == 0) {
    glGenTextures(1, &rgbTexture);
    glBindTexture(GL_TEXTURE_2D, rgbTexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, 1, 1, 0, GL_RGB, GL_UNSIGNED_BYTE, NULL);
  }
  if (programReady && lumaTexture == 0) {
    glGenTextures(1, &lumaTexture);
    glBindTexture(GL_TEXTURE_2D, lumaTexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, 1, 1, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, NULL);
  }
  if (programReady && chromaUTexture == 0) {
    glGenTextures(1, &chromaUTexture);
    glBindTexture(GL_TEXTURE_2D, chromaUTexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, 1, 1, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, NULL);
  }
  if (programReady && chromaVTexture == 0) {
    glGenTextures(1, &chromaVTexture);
    glBindTexture(GL_TEXTURE_2D, chromaVTexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, 1, 1, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, NULL);
  }
  [EAGLContext setCurrentContext:nil];
}

- (BOOL)setupProgram
{
  GLuint vertexShader = 0;
  GLuint fragmentShader = 0;
  if (![self compileShader:XPGLVertexShader type:GL_VERTEX_SHADER output:&vertexShader]) {
    return NO;
  }
  if (![self compileShader:XPGLFragmentShader type:GL_FRAGMENT_SHADER output:&fragmentShader]) {
    glDeleteShader(vertexShader);
    return NO;
  }
  GLuint program = glCreateProgram();
  if (program == 0) {
    glDeleteShader(vertexShader);
    glDeleteShader(fragmentShader);
    return NO;
  }
  glAttachShader(program, vertexShader);
  glAttachShader(program, fragmentShader);
  glLinkProgram(program);
  GLint status = 0;
  glGetProgramiv(program, GL_LINK_STATUS, &status);
  glDeleteShader(vertexShader);
  glDeleteShader(fragmentShader);
  if (status == 0) {
    glDeleteProgram(program);
    return NO;
  }
  shaderProgram = program;
  positionAttribute = glGetAttribLocation(program, "aPosition");
  texCoordAttribute = glGetAttribLocation(program, "aTexCoord");
  lumaUniform = glGetUniformLocation(program, "uLuma");
  chromaUUniform = glGetUniformLocation(program, "uChromaU");
  chromaVUniform = glGetUniformLocation(program, "uChromaV");
  yuvUniform = glGetUniformLocation(program, "uYuv");
  return YES;
}

- (BOOL)compileShader:(NSString *)source type:(GLenum)type output:(GLuint *)shader
{
  GLuint handle = glCreateShader(type);
  if (handle == 0) {
    return NO;
  }
  const char *text = [source UTF8String];
  glShaderSource(handle, 1, &text, NULL);
  glCompileShader(handle);
  GLint status = 0;
  glGetShaderiv(handle, GL_COMPILE_STATUS, &status);
  if (status == 0) {
    glDeleteShader(handle);
    return NO;
  }
  *shader = handle;
  return YES;
}

- (void)dealloc
{
  if (displayLink != nil) {
    [displayLink invalidate];
    displayLink = nil;
  }
}

@end
