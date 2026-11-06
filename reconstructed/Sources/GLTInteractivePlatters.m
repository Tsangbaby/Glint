//
//  GLTInteractivePlatters.m
//  GLTMediaPlatterView + GLTClockPlatterView + GLTComposePlatterView
//
//  The three cards that own a timer or a text field.
//
//  Recovered from 0xdf98 (media), 0x11824 (clock), 0x13514 (compose).
//

#import "Glint.h"
#import "GlintPrivate.h"

static UILabel *GLTMakeLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    return label;
}

static NSString *GLTClockString(double interval) {
    long long total = (long long)MAX(0, interval);
    long long hours = total / 3600;
    long long minutes = (total % 3600) / 60;
    long long seconds = total % 60;
    if (hours > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", hours, minutes, seconds];
    return [NSString stringWithFormat:@"%ld:%02ld", minutes, seconds];
}

#pragma mark - Media

@interface GLTMediaPlatterView ()
- (void)tick;
@end

@implementation GLTMediaPlatterView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    _artworkView = [UIImageView new];
    _artworkView.contentMode = UIViewContentModeScaleAspectFill;
    _artworkView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    _artworkView.layer.cornerRadius = 10;
    _artworkView.layer.cornerCurve = kCACornerCurveContinuous;
    _artworkView.clipsToBounds = YES;
    _artworkView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [_artworkView.widthAnchor constraintEqualToConstant:52],
        [_artworkView.heightAnchor constraintEqualToConstant:52],
    ]];

    _titleLabel = GLTMakeLabel(@"Not Playing", 15, UIFontWeightSemibold, [UIColor whiteColor]);
    _titleLabel.numberOfLines = 1;
    _artistLabel = GLTMakeLabel(@"", 12, UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.55]);
    _artistLabel.numberOfLines = 1;

    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _artistLabel]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 2;

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[_artworkView, text]];
    header.axis = UILayoutConstraintAxisHorizontal;
    header.spacing = 12;
    header.alignment = UIStackViewAlignmentCenter;

    _track = [UIView new];
    _track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
    _track.layer.cornerRadius = 2;
    _fill = [UIView new];
    _fill.backgroundColor = [UIColor whiteColor];
    _fill.layer.cornerRadius = 2;
    [_track addSubview:_fill];

    _elapsedLabel = GLTMakeLabel(@"0:00", 10, UIFontWeightMedium,
                                 [UIColor colorWithWhite:1 alpha:0.45]);
    _remainingLabel = GLTMakeLabel(@"-0:00", 10, UIFontWeightMedium,
                                   [UIColor colorWithWhite:1 alpha:0.45]);
    _remainingLabel.textAlignment = NSTextAlignmentRight;

    UIStackView *times = [[UIStackView alloc] initWithArrangedSubviews:@[_elapsedLabel, _remainingLabel]];
    times.axis = UILayoutConstraintAxisHorizontal;
    times.distribution = UIStackViewDistributionFillEqually;

    UIButton *previous = [self controlWithSymbol:@"backward.fill" size:22 action:@selector(previous)];
    UIButton *play     = [self controlWithSymbol:@"play.fill" size:30 action:@selector(playPause)];
    UIButton *next     = [self controlWithSymbol:@"forward.fill" size:22 action:@selector(next)];
    _playButton = play;

    UIStackView *controls = [[UIStackView alloc] initWithArrangedSubviews:@[previous, play, next]];
    controls.axis = UILayoutConstraintAxisHorizontal;
    controls.distribution = UIStackViewDistributionEqualSpacing;
    controls.alignment = UIStackViewAlignmentCenter;

    UIStackView *body = [[UIStackView alloc] initWithArrangedSubviews:@[header, _track, times, controls]];
    body.axis = UILayoutConstraintAxisVertical;
    body.spacing = 10;

    _track.translatesAutoresizingMaskIntoConstraints = NO;
    [_track.heightAnchor constraintEqualToConstant:4].active = YES;

    [self fillWith:@[body]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refresh)
                                                 name:GLTSourcesDidChangeNotification
                                               object:nil];
    [self refresh];
    return self;
}

- (void)dealloc {
    [_timer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIButton *)controlWithSymbol:(NSString *)symbol size:(double)size action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *image = [UIImage systemImageNamed:symbol
                             withConfiguration:[UIImageSymbolConfiguration
                                                  configurationWithPointSize:size
                                                                      weight:UIFontWeightMedium]];
    [button setImage:image forState:UIControlStateNormal];
    button.tintColor = [UIColor whiteColor];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

// Only refresh the countdown while the card is actually on screen.
- (void)didMoveToWindow {
    [super didMoveToWindow];

    [_timer invalidate];
    _timer = nil;
    if (!self.window) return;

    _timer = [NSTimer scheduledTimerWithTimeInterval:1
                                              target:self
                                            selector:@selector(tick)
                                            userInfo:nil
                                             repeats:YES];
}

- (void)tick {
    [self refresh];
}

- (void)refresh {
    GLTMedia *media = [GLTMedia sharedMedia];

    if (![media hasMedia]) {
        _titleLabel.text = @"Not Playing";
        _artistLabel.text = @"";
        _artworkView.image = GLTSymbol(@"music.note", 24, UIFontWeightRegular);
        _elapsedLabel.text = @"0:00";
        _remainingLabel.text = @"-0:00";
        _fill.frame = CGRectZero;
        [_playButton setImage:[UIImage systemImageNamed:@"play.fill"]
                     forState:UIControlStateNormal];
        return;
    }

    _titleLabel.text = [media title] ?: @"Not Playing";
    _artistLabel.text = [media artist] ?: @"";
    _artworkView.image = [media artwork] ?: GLTSymbol(@"music.note", 24, UIFontWeightRegular);
    _artworkView.contentMode = [media artwork] ? UIViewContentModeScaleAspectFill
                                               : UIViewContentModeCenter;

    double duration = [media duration];
    double elapsed = [media elapsed];
    _fraction = duration > 0 ? MIN(1.0, elapsed / duration) : 0;

    _elapsedLabel.text = GLTClockString(elapsed);
    _remainingLabel.text = [NSString stringWithFormat:@"-%@", GLTClockString(duration - elapsed)];

    [_playButton setImage:[UIImage systemImageNamed:([media isPlaying] ? @"pause.fill" : @"play.fill")]
                 forState:UIControlStateNormal];

    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = CGRectGetWidth(_track.bounds);
    _fill.frame = CGRectMake(0, 0, width * _fraction, CGRectGetHeight(_track.bounds));
}

- (void)playPause {
    [[GLTMedia sharedMedia] togglePlayPause];
}

- (void)next {
    [[GLTMedia sharedMedia] nextTrack];
}

- (void)previous {
    [[GLTMedia sharedMedia] previousTrack];
}

@end

GLTPlatterContent *GLTMakeMediaPlatter(void) {
    return [[GLTMediaPlatterView alloc] initWithFrame:CGRectZero];
}

#pragma mark - Clock (timer + alarms)

@implementation GLTClockPlatterView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    _stack = [UIStackView new];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 8;

    [self fillWith:@[_stack]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(rebuild)
                                                 name:GLTSourcesDidChangeNotification
                                               object:nil];
    [self rebuild];
    return self;
}

- (void)dealloc {
    [_timer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];

    [_timer invalidate];
    _timer = nil;
    if (!self.window) return;

    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        [weakSelf tick];
    }];
}

- (void)rebuild {
    for (UIView *view in _stack.arrangedSubviews) {
        [view removeFromSuperview];
    }

    GLTClockItems *items = [GLTClockItems sharedItems];

    // Timer block.
    if (items.timerFireDate) {
        UILabel *caption = GLTMakeLabel(@"Timer", 13, UIFontWeightSemibold,
                                        [UIColor colorWithWhite:1 alpha:0.55]);
        _countdown = GLTMakeLabel(GLTClockString([items.timerFireDate timeIntervalSinceNow]),
                                  34, UIFontWeightLight, [UIColor whiteColor]);
        _track = [UIView new];
        _track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
        _track.layer.cornerRadius = 2;
        _fill = [UIView new];
        _fill.backgroundColor = [UIColor systemOrangeColor];
        _fill.layer.cornerRadius = 2;
        [_track addSubview:_fill];
        _track.translatesAutoresizingMaskIntoConstraints = NO;
        [_track.heightAnchor constraintEqualToConstant:4].active = YES;

        [_stack addArrangedSubview:caption];
        [_stack addArrangedSubview:_countdown];
        [_stack addArrangedSubview:_track];
    }

    // Alarms block.
    NSArray<GLTAlarm *> *alarms = items.alarms;
    [_stack addArrangedSubview:GLTMakeLabel(@"Alarms", 13, UIFontWeightSemibold,
                                            [UIColor colorWithWhite:1 alpha:0.55])];

    if (alarms.count == 0) {
        [_stack addArrangedSubview:GLTMakeLabel(@"No alarms are on.", 15, UIFontWeightRegular,
                                                [UIColor colorWithWhite:1 alpha:0.7])];
    } else {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEEjmm"
                                                               options:0
                                                                locale:[NSLocale currentLocale]];

        for (GLTAlarm *alarm in [alarms subarrayWithRange:
                                 NSMakeRange(0, MIN((NSUInteger)4, alarms.count))]) {
            UILabel *when = GLTMakeLabel([formatter stringFromDate:alarm.fireDate], 15,
                                         UIFontWeightMedium, [UIColor whiteColor]);
            UILabel *title = GLTMakeLabel(alarm.title.length ? alarm.title : @"Alarm", 12,
                                          UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.5]);
            UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[when, title]];
            column.axis = UILayoutConstraintAxisVertical;
            column.spacing = 1;
            [_stack addArrangedSubview:column];
        }
    }

    [self tick];
}

- (void)tick {
    GLTClockItems *items = [GLTClockItems sharedItems];
    if (!_countdown) return;

    double remaining = [items.timerFireDate timeIntervalSinceNow];
    _countdown.text = GLTClockString(remaining);

    if (items.timerDuration > 0 && CGRectGetWidth(_track.bounds) > 0) {
        double fraction = 1.0 - MAX(0, MIN(1.0, remaining / items.timerDuration));
        _fill.frame = CGRectMake(0, 0, CGRectGetWidth(_track.bounds) * fraction,
                                 CGRectGetHeight(_track.bounds));
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self tick];
}

@end

GLTPlatterContent *GLTMakeClockPlatter(void) {
    return [[GLTClockPlatterView alloc] initWithFrame:CGRectZero];
}

#pragma mark - Compose

@interface GLTComposePlatterView () <UITextFieldDelegate, MFMessageComposeViewControllerDelegate>
@end

@implementation GLTComposePlatterView

- (BOOL)wantsKeyboard {
    return YES;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    _toField = [UITextField new];
    _toField.attributedPlaceholder =
        [[NSAttributedString alloc] initWithString:@"Name or number"
                                        attributes:@{ NSForegroundColorAttributeName:
                                                          [UIColor colorWithWhite:1 alpha:0.35] }];
    _toField.textColor = [UIColor whiteColor];
    _toField.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _toField.autocorrectionType = UITextAutocorrectionTypeNo;
    _toField.returnKeyType = UIReturnKeyNext;
    _toField.delegate = self;
    [_toField addTarget:self action:@selector(searchChanged)
       forControlEvents:UIControlEventEditingChanged];

    _recipientChip = [UIButton buttonWithType:UIButtonTypeSystem];
    _recipientChip.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    _recipientChip.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _recipientChip.tintColor = [UIColor whiteColor];
    _recipientChip.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    _recipientChip.layer.cornerRadius = 11;
    _recipientChip.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
    _recipientChip.hidden = YES;

    _suggestions = [UIStackView new];
    _suggestions.axis = UILayoutConstraintAxisVertical;
    _suggestions.spacing = 4;

    _messageField = [UITextField new];
    _messageField.attributedPlaceholder =
        [[NSAttributedString alloc] initWithString:@"Message"
                                        attributes:@{ NSForegroundColorAttributeName:
                                                          [UIColor colorWithWhite:1 alpha:0.35] }];
    _messageField.textColor = [UIColor whiteColor];
    _messageField.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    _messageField.returnKeyType = UIReturnKeySend;
    _messageField.delegate = self;
    [_messageField addTarget:self action:@selector(updateSendButton)
            forControlEvents:UIControlEventEditingChanged];

    _sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *send = [UIImage systemImageNamed:@"arrow.up.circle.fill"
                            withConfiguration:[UIImageSymbolConfiguration
                                                 configurationWithPointSize:30]];
    [_sendButton setImage:send forState:UIControlStateNormal];
    _sendButton.tintColor = [UIColor systemBlueColor];
    [_sendButton addTarget:self action:@selector(send) forControlEvents:UIControlEventTouchUpInside];
    [_sendButton setContentHuggingPriority:UILayoutPriorityRequired
                                   forAxis:UILayoutConstraintAxisHorizontal];

    _statusLabel = GLTMakeLabel(@"", 11, UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.5]);

    UIStackView *input = [[UIStackView alloc] initWithArrangedSubviews:@[_messageField, _sendButton]];
    input.axis = UILayoutConstraintAxisHorizontal;
    input.spacing = 8;
    input.alignment = UIStackViewAlignmentCenter;

    UIStackView *body = [[UIStackView alloc] initWithArrangedSubviews:
                         @[_toField, _recipientChip, _suggestions, input, _statusLabel]];
    body.axis = UILayoutConstraintAxisVertical;
    body.spacing = 8;

    [self fillWith:@[body]];
    [self updateSendButton];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) return;

    // Becoming first responder immediately fights the presentation animation.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self.window || GLTDeviceIsLocked()) return;
        [self->_toField becomeFirstResponder];
    });
}

- (void)resize {
    [self invalidateIntrinsicContentSize];
    if (self.resizeHandler) self.resizeHandler();
}

#pragma mark - Recipient

- (void)searchChanged {
    NSString *text = _toField.text ?: @"";
    [self showSuggestions:text.length ? GLTSearchRecipients(text) : @[]];
}

- (void)showSuggestions:(NSArray<GLTRecipient *> *)recipients {
    for (UIView *view in _suggestions.arrangedSubviews) {
        [view removeFromSuperview];
    }

    NSUInteger limit = MIN((NSUInteger)4, recipients.count);
    for (NSUInteger i = 0; i < limit; i++) {
        GLTRecipient *recipient = recipients[i];

        NSMutableAttributedString *title =
            [[NSMutableAttributedString alloc] initWithString:recipient.name.length ? recipient.name : recipient.address
                                                   attributes:@{ NSFontAttributeName:
                                                                     [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold],
                                                                 NSForegroundColorAttributeName:[UIColor whiteColor] }];
        if (recipient.name.length && recipient.detail.length) {
            [title appendAttributedString:[[NSAttributedString alloc] initWithString:
                                           [@"  " stringByAppendingString:recipient.detail]
                                                                        attributes:@{ NSFontAttributeName:
                                                                                          [UIFont systemFontOfSize:12],
                                                                                      NSForegroundColorAttributeName:
                                                                                          [UIColor colorWithWhite:1 alpha:0.45] }]];
        }

        UIButton *row = [UIButton buttonWithType:UIButtonTypeSystem];
        [row setAttributedTitle:title forState:UIControlStateNormal];
        row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        row.tag = (NSInteger)i;

        __weak typeof(self) weakSelf = self;
        [row addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
            [weakSelf chooseRecipient:recipient];
        }] forControlEvents:UIControlEventTouchUpInside];

        [_suggestions addArrangedSubview:row];
    }

    _suggestions.hidden = limit == 0;
    [self resize];
}

- (void)chooseRecipient:(GLTRecipient *)recipient {
    _recipient = recipient;
    _toField.hidden = YES;

    NSString *title = recipient.name.length ? recipient.name : recipient.address;
    if (recipient.name.length && recipient.detail.length) {
        title = [NSString stringWithFormat:@"%@ · %@", recipient.name, recipient.detail];
    }
    [_recipientChip setTitle:[@"To: " stringByAppendingString:title] forState:UIControlStateNormal];
    _recipientChip.hidden = NO;

    [self showSuggestions:@[]];
    [_messageField becomeFirstResponder];
    [self updateSendButton];
}

- (void)clearRecipient {
    _recipient = nil;
    _recipientChip.hidden = YES;
    _toField.hidden = NO;
    _toField.text = @"";
    [self showSuggestions:@[]];
    [_toField becomeFirstResponder];
    [self updateSendButton];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == _toField) {
        NSArray *matches = GLTSearchRecipients(_toField.text ?: @"");
        if (matches.count) [self chooseRecipient:matches.firstObject];
        return NO;
    }
    [self send];
    return NO;
}

- (void)updateSendButton {
    NSString *text = [_messageField.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL ready = _recipient != nil && text.length > 0;
    _sendButton.enabled = ready;
    _sendButton.alpha = ready ? 1.0 : 0.4;
}

#pragma mark - Sending

- (void)showStatus:(NSString *)status {
    _statusLabel.text = status;
    _statusLabel.hidden = status.length == 0;
    [self resize];
}

- (void)send {
#if GLINT_VERIFICATION_BUILD
    [self showStatus:@"Messaging is disabled in this verification build."];
    return;
#endif
    if (GLTDeviceIsLocked() || !self.window || _sending) return;
    NSString *text = [_messageField.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!_recipient || !text.length) return;

    [self updateSendButton];
    [self showStatus:@"Sending…"];

    BOOL sent = GLTSendMessage(_recipient, text);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (sent) {
            UINotificationFeedbackGenerator *haptic = [UINotificationFeedbackGenerator new];
            [haptic notificationOccurred:UINotificationFeedbackTypeSuccess];
            [self showStatus:@"Sent"];
            self->_messageField.text = @"";
            [self updateSendButton];

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self close];
            });
        } else {
            [self showStatus:@""];
            [self composeWithApple:NO text:text];
            [self close];
        }
    });
}

// Fallback path: hand the message to the system composer, either as an SMS or
// as an sms: URL when MessageUI is unavailable.
- (void)composeWithApple:(BOOL)apple text:(NSString *)text {
    UIViewController *host = self.window.rootViewController;
    if (!host) return;

    if ([MFMessageComposeViewController canSendText]) {
        MFMessageComposeViewController *composer = [MFMessageComposeViewController new];
        composer.recipients = @[_recipient.address];
        composer.body = text;
        composer.messageComposeDelegate = self;
        [self endEditing:YES];
        [host presentViewController:composer animated:YES completion:nil];
        return;
    }

    NSString *address = [_recipient.address stringByReplacingOccurrencesOfString:@" " withString:@""];
    NSURLComponents *components = [NSURLComponents componentsWithString:@"sms:"];
    components.queryItems = @[[NSURLQueryItem queryItemWithName:@"body" value:text]];
    components.path = address;

    if (components.URL) {
        [[UIApplication sharedApplication] openURL:components.URL options:@{} completionHandler:nil];
    }
}

- (void)messageComposeViewController:(MFMessageComposeViewController *)controller
                didFinishWithResult:(MessageComposeResult)result {
    [controller dismissViewControllerAnimated:YES completion:^{
        [self close];
    }];
}

@end

GLTPlatterContent *GLTMakeComposePlatter(void) {
    return [[GLTComposePlatterView alloc] initWithFrame:CGRectZero];
}
