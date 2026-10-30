function Get-GuiXaml {
    return @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="极速下载助手" Width="960" Height="740" MinWidth="760" MinHeight="600"
        Background="#F5F5F7" FontFamily="Segoe UI, Microsoft YaHei UI" FontSize="14"
        WindowStartupLocation="CenterScreen" UseLayoutRounding="True"
        TextOptions.TextFormattingMode="Display" AllowDrop="True">
    <Window.Resources>
        <Style x:Key="AccentButton" TargetType="Button">
            <Setter Property="Background" Value="#0071E3"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Chrome" Background="{TemplateBinding Background}" CornerRadius="10">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Chrome" Property="Background" Value="#0077ED"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Chrome" Property="Background" Value="#0059B8"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Chrome" Property="Background" Value="#C9C9CE"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="QuietButton" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#0071E3"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Chrome" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Chrome" Property="Background" Value="#EBEBF0"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="SlimProgress" TargetType="ProgressBar">
            <Setter Property="Height" Value="4"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ProgressBar">
                        <Grid>
                            <Border x:Name="PART_Track" Background="#EDEDF2" CornerRadius="2"/>
                            <Border x:Name="PART_Indicator" Background="#0071E3" CornerRadius="2" HorizontalAlignment="Left"/>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="32,28,32,22">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Margin="0,0,0,22">
            <TextBlock Text="极速下载助手" FontSize="27" FontWeight="SemiBold" Foreground="#1D1D1F"/>
            <TextBlock x:Name="Subtitle" Text="粘贴下载链接，按回车开始" FontSize="13" Foreground="#86868B" Margin="0,7,0,0"/>
        </StackPanel>

        <Grid Grid.Row="1" Margin="0,0,0,6">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Border x:Name="InputFrame" Background="#FFFFFF" CornerRadius="11" BorderBrush="#E3E3E8" BorderThickness="1" Height="92">
                <Grid>
                    <TextBox x:Name="UrlBox" Background="Transparent" BorderThickness="0" Margin="14,10" FontSize="14"
                             AcceptsReturn="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"
                             VerticalContentAlignment="Top" Foreground="#1D1D1F" CaretBrush="#0071E3"/>
                    <TextBlock x:Name="Placeholder" Text="https://…  或  magnet:?xt=…  或  拖入种子文件"
                               Foreground="#B0B0B5" FontSize="13.5" Margin="16,14,0,0" VerticalAlignment="Top" IsHitTestVisible="False"/>
                </Grid>
            </Border>
            <Button x:Name="StartButton" Grid.Column="1" Content="开始下载" Width="112" Height="48" Margin="12,0,0,0" Style="{StaticResource AccentButton}"/>
        </Grid>

        <Grid Grid.Row="2" Margin="0,8,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Border CornerRadius="8" BorderBrush="#E3E3E8" BorderThickness="1" Background="White" Padding="10,7">
                <TextBox x:Name="DestinationBox" BorderThickness="0" Background="Transparent" FontSize="12.5" Foreground="#66666C"/>
            </Border>
            <Button x:Name="ChooseFolderButton" Grid.Column="1" Content="保存位置…" Margin="8,0,0,0" Style="{StaticResource QuietButton}"/>
            <Button x:Name="ImportButton" Grid.Column="2" Content="导入文件…" Margin="4,0,0,0" Style="{StaticResource QuietButton}"/>
        </Grid>
        <TextBlock x:Name="Message" Grid.Row="3" Text="" FontSize="12" Foreground="#B34236" Margin="4,5,0,4" Height="22" TextTrimming="CharacterEllipsis"/>

        <Grid Grid.Row="4">
            <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,4,14,0">
                <StackPanel x:Name="TaskPanel"/>
            </ScrollViewer>
            <TextBlock x:Name="EmptyHint" Text="还没有任务" FontSize="14" Foreground="#B0B0B5"
                       HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>

        <Grid Grid.Row="5" Margin="0,16,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel>
                <TextBlock x:Name="FooterInfo" FontSize="12" Foreground="#86868B"/>
                <CheckBox x:Name="NewTaskCheck" Content="另建任务，保留已有下载" FontSize="12" Foreground="#86868B" Margin="0,8,0,0"/>
            </StackPanel>
            <ComboBox x:Name="FilterBox" Grid.Column="1" Width="120" VerticalAlignment="Center">
                <ComboBoxItem Content="全部任务"/><ComboBoxItem Content="下载中 / 排队"/><ComboBoxItem Content="已暂停"/>
                <ComboBoxItem Content="已完成"/><ComboBoxItem Content="待恢复 / 失败"/>
            </ComboBox>
        </Grid>
    </Grid>
</Window>
'@
}

function Get-TaskCardXaml {
    return @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        CornerRadius="12" Background="#FFFFFF" Padding="18,15" Margin="0,0,0,10">
    <Border.Effect>
        <DropShadowEffect BlurRadius="16" ShadowDepth="1" Direction="270" Opacity="0.05" Color="#000000"/>
    </Border.Effect>
    <StackPanel>
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="Title" FontSize="14.5" FontWeight="SemiBold" Foreground="#1D1D1F"
                       TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
            <Border x:Name="Chip" Grid.Column="1" CornerRadius="7" Padding="9,3" Background="#EAF3FE" VerticalAlignment="Center">
                <TextBlock x:Name="ChipText" FontSize="11.5" Foreground="#0071E3"/>
            </Border>
        </Grid>
        <TextBlock x:Name="Meta" Margin="0,7,0,0" FontSize="12" Foreground="#86868B" TextTrimming="CharacterEllipsis"/>
        <ProgressBar x:Name="Bar" Margin="0,12,0,0" Minimum="0" Maximum="100" Value="0"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button x:Name="PauseButton" Content="暂停" Margin="0,0,6,0"/>
            <Button x:Name="ResumeButton" Content="继续" Margin="0,0,6,0"/>
            <Button x:Name="StopButton" Content="停止" Margin="0,0,6,0"/>
            <Button x:Name="OpenButton" Content="打开文件夹"/>
        </StackPanel>
    </StackPanel>
</Border>
'@
}

