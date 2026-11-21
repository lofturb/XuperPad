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
  @"precision mediump float;\n"
  @"varying vec2 vTexCoord;\n"
  @"uniform sampler2D uTexture;\n"
  @"void main() {\n"
  @"gl_FragColor = texture2D(uTexture, vTexCoord);\n"
  @"}\n";

@interface XPGLView () {
  EAGLContext *glContext;
  GLuint shaderProgram;
  GLuint videoTexture;
  GLuint drawFramebuffer;
  GLuint colorRenderbuffer;
  GLint positionAttribute;
  GLint texCoordAttribute;
  GLint textureUniform;
  GLint textureWidth;
  GLint textureHeight;
  NSData *frameData;
  int framePixelWidth;
  int framePixelHeight;
  CADisplayLink *displayLink;
  BOOL programReady;
}

- (void)drawFrame;
- (void)setupFramebuffer;
- (BOOL)setupProgram;
- (BOOL)compileShader:(NSString *)source type:(GLenum)type output:(GLuint *)shader;
- (void)drawQuad;

@end

@implementation XPGLView

+ (Class)layerClass
{
  return [CAEAGLContext class];
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
    programReady = NO;
    EAGLContext *context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (context != nil) {
      [self.layer setValue:context forKey:@"eaglContext"];
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

- (void)displayRGBFrame:(NSData *)rgb width:(int)width height:(int)height
{
  if (width <= 0 || height <= 0) {
    return;
  }
  if (rgb.length < (NSUInteger)(width * height * 3)) {
    return;
  }
  frameData = rgb;
  framePixelWidth = width;
  framePixelHeight = height;
}

- (void)clearFrame
{
  frameData = nil;
  framePixelWidth = 0;
  framePixelHeight = 0;
}

- (void)drawFrame
{
  EAGLContext *context = glContext;
  if (context == nil) {
    return;
  }
  [EAGLContext setCurrentContext:context];
  CGSize size = self.bounds.size;
  glViewport(0, 0, (GLsizei)size.width, (GLsizei)size.height);
  glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);
  NSData *data = frameData;
  if (data != nil && programReady && framePixelWidth > 0 && framePixelHeight > 0) {
    glBindTexture(GL_TEXTURE_2D, videoTexture);
    if (textureWidth != framePixelWidth || textureHeight != framePixelHeight) {
      glTexImage2D(GL_TEXTURE_2D,
                   0,
                   GL_RGB,
                   framePixelWidth,
                   framePixelHeight,
                   0,
                   GL_RGB,
                   GL_UNSIGNED_BYTE,
                   NULL);
      textureWidth = framePixelWidth;
      textureHeight = framePixelHeight;
    }
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexSubImage2D(GL_TEXTURE_2D,
                    0,
                    0,
                    0,
                    framePixelWidth,
                    framePixelHeight,
                    GL_RGB,
                    GL_UNSIGNED_BYTE,
                    data.bytes);
    [self drawQuad];
  }
  glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
  [context presentRenderbuffer:GL_RENDERBUFFER];
}

- (void)drawQuad
{
  CGFloat viewWidth = self.bounds.size.width;
  CGFloat viewHeight = self.bounds.size.height;
  if (viewWidth <= 0.0f || viewHeight <= 0.0f) {
    return;
  }
  double videoAspect = (double)framePixelWidth / (double)framePixelHeight;
  double viewAspect = (double)viewWidth / (double)viewHeight;
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
  glBindTexture(GL_TEXTURE_2D, videoTexture);
  glUniform1i(textureUniform, 0);
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
    glRenderbufferStorage(GL_RENDERBUFFER,
                          GL_RGBA,
                          (GLsizei)size.width,
                          (GLsizei)size.height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER,
                              GL_COLOR_ATTACHMENT0,
                              GL_RENDERBUFFER,
                              colorRenderbuffer);
  }
  if (!programReady) {
    programReady = [self setupProgram];
  }
  if (programReady && videoTexture == 0) {
    glGenTextures(1, &videoTexture);
    glBindTexture(GL_TEXTURE_2D, videoTexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
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
  textureUniform = glGetUniformLocation(program, "uTexture");
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
