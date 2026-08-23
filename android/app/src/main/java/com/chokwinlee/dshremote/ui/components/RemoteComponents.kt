package com.chokwinlee.dshremote.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.theme.RemoteDimens
import com.chokwinlee.dshremote.ui.theme.RemoteTheme

enum class RemoteActionKind {
    Primary,
    Secondary,
    Ghost,
    Destructive,
}

enum class RemoteNoticeTone {
    Information,
    Success,
    Warning,
    Danger,
}

@Composable
fun RemoteSurface(
    modifier: Modifier = Modifier,
    cornerRadius: androidx.compose.ui.unit.Dp = RemoteDimens.rowRadius,
    raised: Boolean = false,
    outlined: Boolean = true,
    content: @Composable () -> Unit,
) {
    val colors = RemoteTheme.colors
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(cornerRadius))
            .background(if (raised) colors.raisedSurface else colors.surface)
            .then(
                if (outlined) {
                    Modifier.border(1.dp, colors.hairline, RoundedCornerShape(cornerRadius))
                } else {
                    Modifier
                },
            ),
    ) {
        content()
    }
}

@Composable
fun RemotePageHeader(
    title: String,
    subtitle: String? = null,
    onBack: (() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
) {
    val colors = RemoteTheme.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.canvas)
            .statusBarsPadding()
            .heightIn(min = 56.dp)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            RemoteIconButton(
                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = androidx.compose.ui.res.stringResource(R.string.action_back),
                onClick = onBack,
            )
        } else {
            Spacer(Modifier.width(6.dp))
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 4.dp)
                .semantics(mergeDescendants = true) { heading() },
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (!subtitle.isNullOrBlank()) {
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        actions()
    }
    Box(
        Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(colors.hairline),
    )
}

@Composable
fun RemoteIconButton(
    imageVector: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    tint: Color = MaterialTheme.colorScheme.onSurface,
    emphasized: Boolean = false,
    enabled: Boolean = true,
) {
    IconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .size(RemoteDimens.toolbarTouchTarget)
            .clip(RoundedCornerShape(RemoteDimens.controlRadius))
            .background(
                when {
                    emphasized -> tint.copy(alpha = 0.10f)
                    else -> Color.Transparent
                },
            ),
    ) {
        Icon(
            imageVector = imageVector,
            contentDescription = contentDescription,
            tint = if (enabled) tint else tint.copy(alpha = 0.42f),
            modifier = Modifier.size(20.dp),
        )
    }
}

@Composable
fun RemoteActionButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: RemoteActionKind = RemoteActionKind.Primary,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    fillsWidth: Boolean = true,
) {
    val colors = RemoteTheme.colors
    val container = when (kind) {
        RemoteActionKind.Primary -> colors.accentFill
        RemoteActionKind.Secondary -> colors.mutedSurface
        RemoteActionKind.Ghost -> Color.Transparent
        RemoteActionKind.Destructive -> colors.danger.copy(alpha = 0.08f)
    }
    val foreground = when (kind) {
        RemoteActionKind.Primary -> colors.accentContent
        RemoteActionKind.Secondary, RemoteActionKind.Ghost -> MaterialTheme.colorScheme.onSurface

        RemoteActionKind.Destructive -> colors.danger
    }
    val shape = RoundedCornerShape(RemoteDimens.controlRadius)

    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .then(if (fillsWidth) Modifier.fillMaxWidth() else Modifier)
            .heightIn(min = 48.dp),
        shape = shape,
        colors = ButtonDefaults.buttonColors(
            containerColor = container,
            contentColor = foreground,
            disabledContainerColor = when (kind) {
                RemoteActionKind.Primary, RemoteActionKind.Secondary -> colors.mutedSurface
                RemoteActionKind.Ghost -> Color.Transparent
                RemoteActionKind.Destructive -> colors.danger.copy(alpha = 0.04f)
            },
            disabledContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
        ),
        elevation = ButtonDefaults.buttonElevation(defaultElevation = 0.dp, pressedElevation = 0.dp),
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(text = text, style = MaterialTheme.typography.labelLarge)
    }
}

@Composable
fun RemoteSectionHeader(
    title: String,
    modifier: Modifier = Modifier,
    detail: String? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) { heading() },
        verticalAlignment = Alignment.Bottom,
        horizontalArrangement = Arrangement.spacedBy(RemoteDimens.space12),
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
            modifier = Modifier.weight(1f),
        )
        if (!detail.isNullOrBlank()) {
            Text(
                text = detail,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
fun RemoteStatusPill(
    text: String,
    color: Color,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(color.copy(alpha = 0.09f))
            .padding(horizontal = 7.dp, vertical = 3.dp)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Box(
            Modifier
                .size(5.dp)
                .clip(RoundedCornerShape(50))
                .background(color),
        )
        Text(
            text = text,
            color = color,
            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
        )
    }
}

@Composable
fun RemoteInlineNotice(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    tone: RemoteNoticeTone = RemoteNoticeTone.Information,
    actionText: String? = null,
    onAction: (() -> Unit)? = null,
) {
    val colors = RemoteTheme.colors
    val toneColor = when (tone) {
        RemoteNoticeTone.Information -> colors.accent
        RemoteNoticeTone.Success -> colors.success
        RemoteNoticeTone.Warning -> colors.warning
        RemoteNoticeTone.Danger -> colors.danger
    }
    val icon = when (tone) {
        RemoteNoticeTone.Information, RemoteNoticeTone.Success -> Icons.Default.Info

        RemoteNoticeTone.Warning, RemoteNoticeTone.Danger -> Icons.Default.ErrorOutline
    }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(RemoteDimens.controlRadius))
            .background(toneColor.copy(alpha = 0.065f))
            .border(1.dp, toneColor.copy(alpha = 0.14f), RoundedCornerShape(RemoteDimens.controlRadius))
            .padding(10.dp)
            .semantics {
                liveRegion = if (tone == RemoteNoticeTone.Danger) {
                    LiveRegionMode.Assertive
                } else {
                    LiveRegionMode.Polite
                }
            },
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = toneColor,
            modifier = Modifier
                .padding(top = 2.dp)
                .size(17.dp),
        )
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Text(text = title, style = MaterialTheme.typography.labelLarge, color = toneColor)
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (actionText != null && onAction != null) {
                TextButton(
                    onClick = onAction,
                    colors = ButtonDefaults.textButtonColors(contentColor = toneColor),
                ) {
                    Text(actionText)
                }
            }
        }
    }
}

@Composable
fun RemoteTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    placeholder: String? = null,
    supportingText: String? = null,
    enabled: Boolean = true,
    singleLine: Boolean = true,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    visualTransformation: VisualTransformation = VisualTransformation.None,
) {
    val colors = RemoteTheme.colors
    TextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier
            .fillMaxWidth()
            .sizeIn(minHeight = 56.dp),
        enabled = enabled,
        label = { Text(label) },
        placeholder = placeholder?.let { { Text(it) } },
        supportingText = supportingText?.let { { Text(it) } },
        singleLine = singleLine,
        shape = RoundedCornerShape(RemoteDimens.controlRadius),
        keyboardOptions = keyboardOptions,
        visualTransformation = visualTransformation,
        colors = TextFieldDefaults.colors(
            focusedContainerColor = colors.surface,
            unfocusedContainerColor = colors.raisedSurface,
            disabledContainerColor = colors.raisedSurface.copy(alpha = 0.55f),
            errorContainerColor = colors.danger.copy(alpha = 0.08f),
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent,
            errorIndicatorColor = Color.Transparent,
        ),
    )
}

@Composable
fun RemoteLoadingState(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 28.dp)
            .semantics { liveRegion = LiveRegionMode.Polite },
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        CircularProgressIndicator(
            modifier = Modifier
                .padding(top = 2.dp)
                .size(20.dp),
            color = RemoteTheme.colors.accent,
            strokeWidth = 2.dp,
        )
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(text = title, style = MaterialTheme.typography.labelLarge)
            Text(
                text = message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
fun RemoteEmptyState(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    icon: ImageVector = Icons.Default.Info,
    actionText: String? = null,
    onAction: (() -> Unit)? = null,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 40.dp),
        horizontalAlignment = Alignment.Start,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = RemoteTheme.colors.accent,
            modifier = Modifier.size(24.dp),
        )
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
        )
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (actionText != null && onAction != null) {
            Spacer(Modifier.height(2.dp))
            RemoteActionButton(
                text = actionText,
                onClick = onAction,
                fillsWidth = false,
                kind = RemoteActionKind.Secondary,
            )
        }
    }
}

@Composable
fun RemoteErrorState(
    message: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    RemoteEmptyState(
        title = androidx.compose.ui.res.stringResource(R.string.state_connection_failed),
        message = message,
        icon = Icons.Default.ErrorOutline,
        actionText = androidx.compose.ui.res.stringResource(R.string.action_retry),
        onAction = onRetry,
        modifier = modifier,
    )
}

@Composable
fun RemoteCloseButton(onClick: () -> Unit) {
    RemoteIconButton(
        imageVector = Icons.Default.Close,
        contentDescription = androidx.compose.ui.res.stringResource(R.string.action_close),
        onClick = onClick,
    )
}
